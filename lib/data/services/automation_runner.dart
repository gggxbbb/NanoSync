import 'dart:async';

import '../models/automation_models.dart';
import 'app_log_service.dart';
import 'automation_service.dart';
import 'new_sync_engine.dart';
import 'repository_manager.dart';
import 'vc_engine.dart';

class AutomationRunner {
  static AutomationRunner? _instance;

  final AutomationService _automationService;
  final RepositoryManager _repositoryManager;
  final NewSyncEngine _syncEngine;
  final AppLogService _appLog;

  Timer? _tickTimer;
  bool _isRunning = false;
  bool _isTickExecuting = false;

  final Map<String, DateTime> _changeDetectedAt = {};

  AutomationRunner._({
    AutomationService? automationService,
    RepositoryManager? repositoryManager,
    NewSyncEngine? syncEngine,
    AppLogService? appLog,
  }) : _automationService = automationService ?? AutomationService.instance,
       _repositoryManager = repositoryManager ?? RepositoryManager.instance,
       _syncEngine = syncEngine ?? NewSyncEngine.instance,
       _appLog = appLog ?? AppLogService.instance;

  static AutomationRunner get instance {
    _instance ??= AutomationRunner._();
    return _instance!;
  }

  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    await _appLog.info(
      category: 'automation',
      message: 'Automation runner started',
      source: 'AutomationRunner.start',
    );

    await _automationService.initializeAutomationTables();
    _isRunning = true;
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) => _runTick());

    unawaited(_runTick());
  }

  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _isRunning = false;
    _changeDetectedAt.clear();
    unawaited(
      _appLog.info(
        category: 'automation',
        message: 'Automation runner stopped',
        source: 'AutomationRunner.stop',
      ),
    );
  }

  Future<void> _runTick() async {
    if (_isTickExecuting) {
      return;
    }

    _isTickExecuting = true;
    try {
      final now = DateTime.now();
      final rules = await _automationService.getAllEnabledRules();
      await _appLog.debug(
        category: 'automation',
        message: 'Automation tick',
        source: 'AutomationRunner._runTick',
        context: {'enabledRules': rules.length},
      );

      for (final rule in rules) {
        try {
          await _tryExecuteRule(rule, now);
        } catch (e) {
          await _appLog.error(
            category: 'automation',
            message: 'Automation rule execution failed',
            source: 'AutomationRunner._runTick',
            repositoryId: rule.repositoryId,
            details: e.toString(),
            context: {'ruleId': rule.id, 'ruleName': rule.name},
          );
          // Isolate each rule execution and keep runner alive.
        }
      }
    } finally {
      _isTickExecuting = false;
    }
  }

  Future<void> _tryExecuteRule(AutomationRule rule, DateTime now) async {
    await _appLog.debug(
      category: 'automation',
      message: 'Evaluate automation rule',
      source: 'AutomationRunner._tryExecuteRule',
      repositoryId: rule.repositoryId,
      context: {
        'ruleId': rule.id,
        'name': rule.name,
        'trigger': rule.triggerType.name,
        'action': rule.actionType.name,
      },
    );

    final repo = await _repositoryManager.getRepository(rule.repositoryId);
    if (repo == null) {
      return;
    }

    if (rule.triggerType == AutomationTriggerType.timeBased) {
      final interval = Duration(minutes: rule.intervalMinutes ?? 30);
      final lastTriggered = rule.lastTriggeredAt ?? rule.createdAt;
      if (now.difference(lastTriggered) < interval) {
        return;
      }

      final executed = await _runWithRetry(
        rule,
        () => _executeByRuleConfiguration(rule, repo),
      );
      if (!executed) {
        return;
      }
      await _automationService.updateLastTriggered(rule.id);
      return;
    }

    final statusResult = await VcEngine(repositoryId: repo.id).status();
    if (!statusResult.isSuccess || statusResult.data is! VcRepositoryStatus) {
      return;
    }

    final status = statusResult.data as VcRepositoryStatus;
    if (status.isClean) {
      _changeDetectedAt.remove(rule.id);
      return;
    }

    final firstDetected = _changeDetectedAt.putIfAbsent(rule.id, () => now);
    final debounce = Duration(seconds: rule.debounceSeconds ?? 300);
    if (now.difference(firstDetected) < debounce) {
      return;
    }

    final executed = await _runWithRetry(
      rule,
      () => _executeByRuleConfiguration(rule, repo),
    );
    if (!executed) {
      return;
    }
    _changeDetectedAt.remove(rule.id);
    await _automationService.updateLastTriggered(rule.id);
  }

  Future<bool> _runWithRetry(
    AutomationRule rule,
    Future<void> Function() action,
  ) async {
    final attempts = rule.retryCount < 1 ? 1 : rule.retryCount;
    final delaySeconds = rule.retryDelaySeconds < 0
        ? 0
        : rule.retryDelaySeconds;
    Object? lastError;

    for (var i = 0; i < attempts; i++) {
      try {
        await action();
        await _appLog.debug(
          category: 'automation',
          message: 'Automation action succeeded',
          source: 'AutomationRunner._runWithRetry',
          repositoryId: rule.repositoryId,
          context: {'ruleId': rule.id, 'attempt': i + 1},
        );
        return true;
      } catch (e) {
        lastError = e;
        await _appLog.warning(
          category: 'automation',
          message: 'Automation action retry',
          source: 'AutomationRunner._runWithRetry',
          repositoryId: rule.repositoryId,
          details: e.toString(),
          context: {'ruleId': rule.id, 'attempt': i + 1, 'max': attempts},
        );
        if (i == attempts - 1) {
          break;
        }
        if (delaySeconds > 0) {
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    }

    if (lastError != null) {
      throw StateError('Automation execution failed: $lastError');
    }
    return false;
  }

  Future<void> _executeByRuleConfiguration(
    AutomationRule rule,
    Repository repo,
  ) async {
    // Change-based trigger cannot observe remote-side changes, so sync is invalid.
    if (rule.triggerType == AutomationTriggerType.changeBased &&
        rule.actionType == AutomationActionType.sync) {
      return;
    }

    if (rule.triggerType == AutomationTriggerType.timeBased) {
      final doCommit = rule.autoCommitOnInterval == true;
      final doPush = rule.autoPushOnInterval == true;

      if (doCommit || doPush) {
        final committed = doCommit ? await _autoCommit(rule, repo) : false;
        if (doPush) {
          // Push even without a new commit to allow publishing previously local commits.
          await _syncEngine.push(repo);
        } else if (committed) {
          // no-op
        }
        return;
      }
    }

    if (rule.triggerType == AutomationTriggerType.changeBased) {
      final doCommit = rule.commitOnChange == true;
      final doPush = rule.pushAfterCommit == true;

      if (doCommit || doPush) {
        final committed = doCommit ? await _autoCommit(rule, repo) : false;
        if (doPush && (committed || !doCommit)) {
          await _syncEngine.push(repo);
        }
        return;
      }
    }

    await _executeActionType(rule.actionType, rule, repo);
  }

  Future<void> _executeActionType(
    AutomationActionType actionType,
    AutomationRule rule,
    Repository repo,
  ) async {
    switch (actionType) {
      case AutomationActionType.commit:
        await _autoCommit(rule, repo);
        break;
      case AutomationActionType.push:
        await _syncEngine.push(repo);
        break;
      case AutomationActionType.commitAndPush:
        await _autoCommit(rule, repo);
        await _syncEngine.push(repo);
        break;
      case AutomationActionType.pull:
        await _syncEngine.pull(repo);
        break;
      case AutomationActionType.sync:
        await _syncEngine.sync(repo);
        break;
    }
  }

  Future<bool> _autoCommit(AutomationRule rule, Repository repo) async {
    await _appLog.info(
      category: 'automation',
      message: 'Automation auto-commit started',
      source: 'AutomationRunner._autoCommit',
      repositoryId: repo.id,
      context: {'ruleId': rule.id, 'ruleName': rule.name},
    );

    final engine = VcEngine(repositoryId: repo.id);
    final addResult = await engine.add(all: true);
    if (addResult.result == VcOperationResult.nothingToCommit) {
      return false;
    }
    if (!addResult.isSuccess) {
      throw StateError(addResult.message);
    }

    final fileCount = addResult.data is int ? addResult.data as int : 0;
    final message = _automationService.resolveCommitMessageTemplate(
      rule.commitMessageTemplate,
      repositoryName: repo.name,
      fileCount: fileCount,
      additions: 0,
      deletions: 0,
    );

    final commitResult = await engine.commit(message: message);
    if (commitResult.result == VcOperationResult.nothingToCommit) {
      return false;
    }
    if (!commitResult.isSuccess) {
      throw StateError(commitResult.message);
    }

    await _appLog.info(
      category: 'automation',
      message: 'Automation auto-commit completed',
      source: 'AutomationRunner._autoCommit',
      repositoryId: repo.id,
      context: {'ruleId': rule.id, 'message': message},
    );

    return true;
  }
}
