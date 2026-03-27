import 'package:fluent_ui/fluent_ui.dart' hide ComboBoxItem;
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:provider/provider.dart';
import '../../data/models/automation_models.dart';
import '../../data/services/automation_service.dart';
import '../../data/services/automation_runner.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/vc_repository_provider.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/safe_combo_box.dart';
import 'package:uuid/uuid.dart';

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  final _automationService = AutomationService.instance;
  List<AutomationRule> _rules = [];
  bool _loading = false;
  String? _selectedRepositoryId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndLoadRules();
    });
  }

  Future<void> _initializeAndLoadRules() async {
    await _automationService.initializeAutomationTables();
    final vcProvider = context.read<VcRepositoryProvider>();
    if (vcProvider.repositories.isNotEmpty) {
      _selectedRepositoryId = vcProvider.repositories.first.id;
      if (mounted) {
        await _loadRules();
      }
    }
  }

  Future<void> _loadRules() async {
    if (_selectedRepositoryId == null) return;

    setState(() => _loading = true);
    try {
      final rules = await _automationService.getAutomationRulesByRepository(
        _selectedRepositoryId!,
      );
      if (mounted) {
        setState(() => _rules = rules);
      }
    } catch (e) {
      _showError('加载自动化规则失败: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncRunnerState() async {
    final hasEnabled = await _automationService.hasEnabledRules();
    if (hasEnabled) {
      await AutomationRunner.instance.start();
    } else {
      AutomationRunner.instance.stop();
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          Button(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.teal),
    );
  }

  void _showCreateRuleDialog() {
    final vcProvider = context.read<VcRepositoryProvider>();
    final repoName = vcProvider.repositories
        .firstWhere((r) => r.id == _selectedRepositoryId)
        .name;

    showDialog(
      context: context,
      builder: (context) => _AutomationRuleDialog(
        repositoryId: _selectedRepositoryId!,
        repositoryName: repoName,
        onSave: (rule) async {
          await _automationService.saveAutomationRule(rule);
          await _syncRunnerState();
          _showSuccess('自动化规则已创建');
          if (mounted) {
            Navigator.pop(context);
            await _loadRules();
          }
        },
      ),
    );
  }

  void _showEditRuleDialog(AutomationRule rule) {
    final vcProvider = context.read<VcRepositoryProvider>();
    final repoName = vcProvider.repositories
        .firstWhere((r) => r.id == _selectedRepositoryId)
        .name;

    showDialog(
      context: context,
      builder: (context) => _AutomationRuleDialog(
        repositoryId: _selectedRepositoryId!,
        repositoryName: repoName,
        initialRule: rule,
        onSave: (updatedRule) async {
          await _automationService.saveAutomationRule(updatedRule);
          await _syncRunnerState();
          _showSuccess('自动化规则已更新');
          if (mounted) {
            Navigator.pop(context);
            await _loadRules();
          }
        },
      ),
    );
  }

  Future<void> _deleteRule(AutomationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('删除规则'),
        content: Text('确定要删除规则 "${rule.name}" 吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('删除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _automationService.deleteAutomationRule(rule.id);
      await _syncRunnerState();
      _showSuccess('规则已删除');
      await _loadRules();
    }
  }

  Future<void> _toggleRule(AutomationRule rule) async {
    await _automationService.setAutomationRuleEnabled(rule.id, !rule.enabled);
    await _syncRunnerState();
    await _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vcProvider = context.watch<VcRepositoryProvider>();

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('自动化配置'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: _loading ? null : _loadRules,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('新建规则'),
              onPressed: _selectedRepositoryId == null
                  ? null
                  : _showCreateRuleDialog,
            ),
          ],
        ),
      ),
      content: Column(
        children: [
          // Repository selector
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppStyles.borderColor(isDark)),
              ),
            ),
            child: Row(
              children: [
                const Icon(FluentIcons.folder_open, size: 16),
                const SizedBox(width: 8),
                Text(
                  '选择仓库: ',
                  style: AppStyles.textStyleBody.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SafeComboBox<String>(
                    value: _selectedRepositoryId,
                    isExpanded: true,
                    emptyPlaceholder: '暂无已注册仓库，请先在"仓库"页面导入仓库',
                    items: vcProvider.repositories
                        .map(
                          (repo) => ComboBoxItem(
                            value: repo.id,
                            child: Text(repo.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRepositoryId = value);
                        _loadRules();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // Rules list
          Expanded(
            child: vcProvider.repositories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.folder_open, size: 64),
                        const SizedBox(height: 16),
                        Text('暂无已注册仓库', style: AppStyles.textStyleSubtitle),
                        const SizedBox(height: 8),
                        Text(
                          '请先在"仓库"页面导入或克隆仓库',
                          style: AppStyles.textStyleBody.copyWith(
                            color: AppStyles.lightTextSecondary(isDark),
                          ),
                        ),
                      ],
                    ),
                  )
                : _loading
                ? const Center(child: ProgressRing())
                : _rules.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.settings, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          '暂无自动化规则',
                          style: AppStyles.textStyleBody.copyWith(
                            color: AppStyles.lightTextSecondary(isDark),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Button(
                          onPressed: _showCreateRuleDialog,
                          child: const Text('创建第一个规则'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _rules.length,
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      return _buildRuleCard(rule, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(AutomationRule rule, bool isDark) {
    final triggerLabel = rule.triggerType == AutomationTriggerType.timeBased
        ? '定时 (${rule.intervalMinutes} 分钟)'
        : '修改时触发';
    final actionLabel = _actionTypeLabel(rule.actionType);

    return AppCardSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          rule.name,
                          style: AppStyles.textStyleButton.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: rule.enabled
                                ? Colors.teal.withAlpha(100)
                                : Colors.grey.withAlpha(100),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rule.enabled ? '已启用' : '已禁用',
                            style: AppStyles.textStyleCaption.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: rule.enabled
                                  ? Colors.teal.dark
                                  : (isDark
                                        ? Colors.grey[100]
                                        : Colors.grey[130]),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildBadge(
                          '触发: $triggerLabel',
                          Colors.blue.withAlpha(50),
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildBadge(
                          '操作: $actionLabel',
                          Colors.green.withAlpha(50),
                          isDark,
                        ),
                      ],
                    ),
                    if (rule.commitMessageTemplate.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[80] : Colors.grey[20],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(FluentIcons.message, size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '提交模板: ${rule.commitMessageTemplate}',
                                style: AppStyles.textStyleCaption.copyWith(
                                  color: AppStyles.lightTextSecondary(isDark),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (rule.lastTriggeredAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '最后触发: ${_formatTime(rule.lastTriggeredAt!)}',
                        style: AppStyles.textStyleCaption.copyWith(
                          color: AppStyles.lightTextSecondary(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  ToggleSwitch(
                    checked: rule.enabled,
                    onChanged: (value) => _toggleRule(rule),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(FluentIcons.edit),
                    onPressed: () => _showEditRuleDialog(rule),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(FluentIcons.delete),
                    onPressed: () => _deleteRule(rule),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _actionTypeLabel(AutomationActionType type) {
    switch (type) {
      case AutomationActionType.commit:
        return '自动提交';
      case AutomationActionType.push:
        return '自动推送';
      case AutomationActionType.commitAndPush:
        return '提交并推送';
      case AutomationActionType.pull:
        return '自动拉取';
      case AutomationActionType.sync:
        return '双向同步';
    }
  }

  Widget _buildBadge(String text, Color bgColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppStyles.textStyleCaption.copyWith(
          fontSize: 10,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return '刚刚';
        }
        return '${diff.inMinutes} 分钟前';
      }
      return '${diff.inHours} 小时前';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return time.toString().split(' ')[0];
    }
  }
}

class _AutomationRuleDialog extends StatefulWidget {
  final String repositoryId;
  final String repositoryName;
  final AutomationRule? initialRule;
  final Function(AutomationRule) onSave;

  const _AutomationRuleDialog({
    required this.repositoryId,
    required this.repositoryName,
    this.initialRule,
    required this.onSave,
  });

  @override
  State<_AutomationRuleDialog> createState() => _AutomationRuleDialogState();
}

class _AutomationRuleDialogState extends State<_AutomationRuleDialog> {
  late TextEditingController _nameController;
  late TextEditingController _templateController;
  late AutomationTriggerType _triggerType;
  late AutomationActionType _actionType;
  late int _intervalMinutes;
  late int _debounceSeconds;
  late int _retryCount;
  late int _retryDelaySeconds;
  late bool _autoCommitOnInterval;
  late bool _autoPushOnInterval;
  late bool _commitOnChange;
  late bool _pushAfterCommit;

  final List<String> _templateVariables = [
    '{repo_name}',
    '{file_count}',
    '{additions}',
    '{deletions}',
    '{timestamp}',
    '{date}',
    '{time}',
    '{branch}',
    '{changes_summary}',
  ];

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _templateController = TextEditingController(
      text:
          rule?.commitMessageTemplate ??
          'chore({repo_name}): auto-commit - {file_count} files changed',
    );
    _triggerType = rule?.triggerType ?? AutomationTriggerType.timeBased;
    _actionType = rule?.actionType ?? AutomationActionType.commit;
    _intervalMinutes = rule?.intervalMinutes ?? 30;
    _debounceSeconds = rule?.debounceSeconds ?? 300;
    _retryCount = rule?.retryCount ?? 3;
    _retryDelaySeconds = rule?.retryDelaySeconds ?? 5;
    _autoCommitOnInterval = rule?.autoCommitOnInterval ?? true;
    _autoPushOnInterval = rule?.autoPushOnInterval ?? false;
    _commitOnChange = rule?.commitOnChange ?? false;
    _pushAfterCommit = rule?.pushAfterCommit ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  String _getPreviewText() {
    String preview = _templateController.text;

    // 替换变量为示例值
    preview = preview.replaceAll('{repo_name}', widget.repositoryName);
    preview = preview.replaceAll('{file_count}', '5');
    preview = preview.replaceAll('{additions}', '+42');
    preview = preview.replaceAll('{deletions}', '-10');
    preview = preview.replaceAll(
      '{timestamp}',
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    preview = preview.replaceAll(
      '{date}',
      DateTime.now().toString().split(' ')[0],
    );
    preview = preview.replaceAll(
      '{time}',
      DateTime.now().toString().split(' ')[1].split('.')[0],
    );
    preview = preview.replaceAll('{branch}', 'main');
    preview = preview.replaceAll(
      '{changes_summary}',
      'modified: file1.txt, file2.dart',
    );

    return preview;
  }

  String _actionTypeLabel(AutomationActionType type) {
    switch (type) {
      case AutomationActionType.commit:
        return '自动提交';
      case AutomationActionType.push:
        return '自动推送';
      case AutomationActionType.commitAndPush:
        return '提交并推送';
      case AutomationActionType.pull:
        return '自动拉取';
      case AutomationActionType.sync:
        return '双向同步';
    }
  }

  List<AutomationActionType> get _availableActionTypes {
    if (_triggerType == AutomationTriggerType.changeBased) {
      return AutomationActionType.values
          .where((t) => t != AutomationActionType.sync)
          .toList();
    }
    return AutomationActionType.values;
  }

  void _insertVariable(String variable) {
    final text = _templateController.text;
    final selection = _templateController.selection;

    String newText;
    if (selection.start >= 0 && selection.end >= 0) {
      newText = text.replaceRange(selection.start, selection.end, variable);
    } else {
      newText = text + variable;
    }

    _templateController.text = newText;
    _templateController.selection = TextSelection.collapsed(
      offset:
          (selection.start >= 0 ? selection.start : text.length) +
          variable.length,
    );
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('错误'),
          content: const Text('请输入规则名称'),
          actions: [
            Button(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final now = DateTime.now();
    final rule = AutomationRule(
      id: widget.initialRule?.id ?? const Uuid().v4(),
      repositoryId: widget.repositoryId,
      name: _nameController.text.trim(),
      enabled: true,
      triggerType: _triggerType,
      actionType: _actionType,
      intervalMinutes: _triggerType == AutomationTriggerType.timeBased
          ? _intervalMinutes
          : null,
      autoCommitOnInterval: _autoCommitOnInterval,
      autoPushOnInterval: _autoPushOnInterval,
      commitOnChange: _triggerType == AutomationTriggerType.changeBased
          ? _commitOnChange
          : null,
      pushAfterCommit: _pushAfterCommit,
      debounceSeconds: _triggerType == AutomationTriggerType.changeBased
          ? _debounceSeconds
          : null,
      retryCount: _retryCount,
      retryDelaySeconds: _retryDelaySeconds,
      commitMessageTemplate: _templateController.text.trim(),
      createdAt: widget.initialRule?.createdAt ?? now,
      lastTriggeredAt: widget.initialRule?.lastTriggeredAt,
      updatedAt: now,
    );

    widget.onSave(rule);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return ContentDialog(
      title: Text(
        widget.initialRule == null ? '创建自动化规则' : '编辑自动化规则',
        style: AppStyles.textStyleSubtitle.copyWith(
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 规则名称
            Text(
              '规则名称',
              style: AppStyles.textStyleCaption.copyWith(
                color: isDark ? Colors.grey[100] : Colors.grey[140],
              ),
            ),
            const SizedBox(height: 6),
            TextBox(controller: _nameController, placeholder: '例如: 每日自动提交'),
            const SizedBox(height: 16),

            // 触发方式
            Text(
              '触发方式',
              style: AppStyles.textStyleCaption.copyWith(
                color: isDark ? Colors.grey[100] : Colors.grey[140],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ToggleButton(
                    checked: _triggerType == AutomationTriggerType.timeBased,
                    onChanged: (value) {
                      if (value) {
                        setState(() {
                          _triggerType = AutomationTriggerType.timeBased;
                        });
                      }
                    },
                    child: const Text('定时触发'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ToggleButton(
                    checked: _triggerType == AutomationTriggerType.changeBased,
                    onChanged: (value) {
                      if (value) {
                        setState(() {
                          _triggerType = AutomationTriggerType.changeBased;
                          if (_actionType == AutomationActionType.sync) {
                            _actionType = AutomationActionType.commitAndPush;
                          }
                        });
                      }
                    },
                    child: const Text('修改时触发'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              '执行动作',
              style: AppStyles.textStyleCaption.copyWith(
                color: isDark ? Colors.grey[100] : Colors.grey[140],
              ),
            ),
            const SizedBox(height: 6),
            SafeComboBox<AutomationActionType>(
              value: _actionType,
              isExpanded: true,
              items: _availableActionTypes
                  .map(
                    (type) => ComboBoxItem(
                      value: type,
                      child: Text(_actionTypeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _actionType = value);
                }
              },
            ),
            if (_triggerType == AutomationTriggerType.changeBased)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '提示：修改时触发无法感知远端变更，因此不支持“双向同步”。',
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.lightTextSecondary(isDark),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // 触发条件配置
            if (_triggerType == AutomationTriggerType.timeBased) ...[
              Text(
                '间隔时间 (分钟)',
                style: AppStyles.textStyleCaption.copyWith(
                  color: isDark ? Colors.grey[100] : Colors.grey[140],
                ),
              ),
              const SizedBox(height: 6),
              NumberBox(
                value: _intervalMinutes.toDouble(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _intervalMinutes = value.toInt());
                  }
                },
                min: 1,
                max: 1440,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Checkbox(
                      checked: _autoCommitOnInterval,
                      onChanged: (value) {
                        setState(() => _autoCommitOnInterval = value ?? false);
                      },
                      content: const Text('自动提交'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Checkbox(
                      checked: _autoPushOnInterval,
                      onChanged: (value) {
                        setState(() => _autoPushOnInterval = value ?? false);
                      },
                      content: const Text('自动推送'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Checkbox(
                      checked: _commitOnChange,
                      onChanged: (value) {
                        setState(() => _commitOnChange = value ?? false);
                      },
                      content: const Text('修改时自动提交'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '防抖延迟 (秒)',
                style: AppStyles.textStyleCaption.copyWith(
                  color: isDark ? Colors.grey[100] : Colors.grey[140],
                ),
              ),
              const SizedBox(height: 6),
              NumberBox(
                value: _debounceSeconds.toDouble(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _debounceSeconds = value.toInt());
                  }
                },
                min: 1,
                max: 3600,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Checkbox(
                      checked: _pushAfterCommit,
                      onChanged: (value) {
                        setState(() => _pushAfterCommit = value ?? false);
                      },
                      content: const Text('提交后推送'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            Text(
              '失败重试',
              style: AppStyles.textStyleCaption.copyWith(
                color: isDark ? Colors.grey[100] : Colors.grey[140],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: '重试次数',
                    child: NumberBox(
                      value: _retryCount.toDouble(),
                      min: 1,
                      max: 10,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _retryCount = value.toInt());
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: '等待秒数',
                    child: NumberBox(
                      value: _retryDelaySeconds.toDouble(),
                      min: 0,
                      max: 300,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _retryDelaySeconds = value.toInt());
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Commit Message 模板区域
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppStyles.borderColor(isDark)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FluentIcons.message,
                        size: 16,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '提交信息模板',
                        style: AppStyles.textStyleButton.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 模板输入框
                  TextBox(
                    controller: _templateController,
                    placeholder: '输入提交信息模板...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),

                  // 可用变量
                  Text(
                    '可用变量 (点击插入):',
                    style: AppStyles.textStyleCaption.copyWith(
                      color: isDark ? Colors.grey[100] : Colors.grey[140],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _templateVariables.map((v) {
                      return Tooltip(
                        message: _getVariableDescription(v),
                        child: HyperlinkButton(
                          onPressed: () => _insertVariable(v),
                          child: Text(
                            v,
                            style: AppStyles.textStyleCaption.copyWith(
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 预览区域
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[80] : Colors.grey[20],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FluentIcons.preview,
                              size: 12,
                              color: AppStyles.lightTextSecondary(isDark),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '预览效果:',
                              style: AppStyles.textStyleCaption.copyWith(
                                color: AppStyles.lightTextSecondary(isDark),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getPreviewText(),
                          style: AppStyles.textStyleBody.copyWith(
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 常用模板
            Text(
              '常用模板:',
              style: AppStyles.textStyleCaption.copyWith(
                color: isDark ? Colors.grey[100] : Colors.grey[140],
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTemplatePreset('简单提交', 'chore({repo_name}): auto-commit'),
                _buildTemplatePreset(
                  '详细提交',
                  'chore({repo_name}): {file_count} files - {additions}/{deletions}',
                ),
                _buildTemplatePreset(
                  '带时间戳',
                  '[{date}] {repo_name} auto-commit - {changes_summary}',
                ),
                _buildTemplatePreset(
                  '语义化',
                  'chore({branch}): auto-sync {repo_name} at {time}',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(child: const Text('保存'), onPressed: _save),
      ],
    );
  }

  Widget _buildTemplatePreset(String name, String template) {
    return Button(
      onPressed: () {
        _templateController.text = template;
        setState(() {});
      },
      child: Text(name, style: AppStyles.textStyleCaption),
    );
  }

  String _getVariableDescription(String variable) {
    switch (variable) {
      case '{repo_name}':
        return '仓库名称';
      case '{file_count}':
        return '变更文件数量';
      case '{additions}':
        return '新增行数';
      case '{deletions}':
        return '删除行数';
      case '{timestamp}':
        return 'Unix时间戳';
      case '{date}':
        return '日期 (YYYY-MM-DD)';
      case '{time}':
        return '时间 (HH:MM:SS)';
      case '{branch}':
        return '当前分支名';
      case '{changes_summary}':
        return '变更文件摘要';
      default:
        return '';
    }
  }
}
