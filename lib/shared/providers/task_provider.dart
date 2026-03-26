import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/enums.dart';
import '../../data/models/sync_task.dart';
import '../../data/models/sync_log.dart';
import '../../data/database/database_helper.dart';
import '../../data/services/sync_engine.dart';

/// 任务管理Provider
class TaskProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<SyncTask> _tasks = [];
  bool _isLoading = false;
  String? _error;
  SyncEngine? _currentEngine;
  final Map<String, Timer> _scheduledTimers = {};
  final Map<String, StreamSubscription> _fileWatchers = {};

  List<SyncTask> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasRunningTask => _tasks.any((t) => t.isRunning);

  List<SyncTask> get enabledTasks => _tasks.where((t) => t.isEnabled).toList();
  List<SyncTask> get runningTasks => _tasks.where((t) => t.isRunning).toList();

  /// 加载所有任务
  Future<void> loadTasks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final maps = await _db.getAllTasks();
      _tasks = maps.map((m) => SyncTask.fromMap(m)).toList();
      _setupScheduledTasks();
    } catch (e) {
      _error = '加载任务失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 添加任务
  Future<SyncTask?> addTask(SyncTask task) async {
    try {
      await _db.insertTask(task.toMap());
      _tasks.insert(0, task);
      _setupScheduledTask(task);
      notifyListeners();
      return task;
    } catch (e) {
      _error = '添加任务失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 更新任务
  Future<bool> updateTask(SyncTask task) async {
    try {
      task.updatedAt = DateTime.now();
      await _db.updateTask(task.id, task.toMap());
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task;
      }
      _setupScheduledTask(task);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '更新任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 删除任务
  Future<bool> deleteTask(String taskId) async {
    try {
      await _db.deleteTask(taskId);
      _tasks.removeWhere((t) => t.id == taskId);
      _scheduledTimers[taskId]?.cancel();
      _scheduledTimers.remove(taskId);
      _fileWatchers[taskId]?.cancel();
      _fileWatchers.remove(taskId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 批量删除任务
  Future<int> batchDeleteTasks(List<String> taskIds) async {
    int deleted = 0;
    for (final id in taskIds) {
      if (await deleteTask(id)) deleted++;
    }
    return deleted;
  }

  /// 批量启用/禁用任务
  Future<void> batchSetEnabled(List<String> taskIds, bool enabled) async {
    for (final id in taskIds) {
      final task = _tasks.firstWhere((t) => t.id == id);
      task.isEnabled = enabled;
      await updateTask(task);
    }
  }

  /// 执行同步
  Future<SyncLog?> runSync(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.isRunning) return null;

    _currentEngine = SyncEngine(
      onProgress: (progress, message) {
        task.syncProgress = progress;
        notifyListeners();
      },
      onComplete: (log) {
        notifyListeners();
      },
      onError: (error) {
        task.lastError = error;
        notifyListeners();
      },
    );

    final log = await _currentEngine!.executeSync(task);
    _currentEngine = null;
    notifyListeners();
    return log;
  }

  /// 批量执行同步
  Future<void> batchRunSync(List<String> taskIds) async {
    for (final id in taskIds) {
      if (!_tasks.firstWhere((t) => t.id == id).isRunning) {
        await runSync(id);
      }
    }
  }

  /// 取消当前同步
  void cancelCurrentSync() {
    _currentEngine?.cancel();
  }

  /// 暂停当前同步
  void pauseCurrentSync() {
    _currentEngine?.pause();
  }

  /// 继续当前同步
  void resumeCurrentSync() {
    _currentEngine?.resume();
  }

  /// 设置定时任务
  void _setupScheduledTasks() {
    for (final task in _tasks) {
      if (task.isEnabled) {
        _setupScheduledTask(task);
      }
    }
  }

  /// 设置单个定时任务
  void _setupScheduledTask(SyncTask task) {
    _scheduledTimers[task.id]?.cancel();

    if (!task.isEnabled || task.syncTrigger != SyncTrigger.scheduled) return;
    if (task.scheduleType == null || task.scheduleInterval == null) return;

    Duration interval;
    switch (task.scheduleType!) {
      case ScheduleType.minutes:
        interval = Duration(minutes: task.scheduleInterval!);
        break;
      case ScheduleType.hours:
        interval = Duration(hours: task.scheduleInterval!);
        break;
      case ScheduleType.days:
        interval = Duration(days: task.scheduleInterval!);
        break;
      case ScheduleType.weeks:
        interval = Duration(days: task.scheduleInterval! * 7);
        break;
      case ScheduleType.months:
        interval = Duration(days: task.scheduleInterval! * 30);
        break;
    }

    _scheduledTimers[task.id] = Timer.periodic(interval, (_) {
      if (task.isEnabled && !task.isRunning) {
        runSync(task.id);
      }
    });

    task.nextSyncTime = DateTime.now().add(interval);
  }

  /// 获取任务
  SyncTask? getTask(String taskId) {
    try {
      return _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    for (final sub in _fileWatchers.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
