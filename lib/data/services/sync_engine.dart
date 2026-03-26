import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/sync_task.dart';
import '../models/file_snapshot.dart';
import '../models/file_version.dart';
import '../models/sync_log.dart';
import '../database/database_helper.dart';
import '../../core/constants/enums.dart';
import '../../core/constants/app_constants.dart';
import 'file_scanner_service.dart';
import 'webdav_service.dart';
import 'version_service.dart';

/// 同步引擎 - 核心同步逻辑
class SyncEngine {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FileScannerService _scanner = FileScannerService();
  final WebDAVService _webdav = WebDAVService();
  final VersionService _versionService = VersionService();

  /// 同步进度回调
  final void Function(double progress, String message)? onProgress;

  /// 同步完成回调
  final void Function(SyncLog log)? onComplete;

  /// 同步错误回调
  final void Function(String error)? onError;

  bool _isCancelled = false;
  bool _isPaused = false;
  SyncLog? _currentLog;

  SyncEngine({this.onProgress, this.onComplete, this.onError});

  /// 执行同步任务
  Future<SyncLog?> executeSync(SyncTask task) async {
    _isCancelled = false;
    _isPaused = false;

    _currentLog = SyncLog(
      taskId: task.id,
      taskName: task.name,
    );

    try {
      _reportProgress(0.0, '开始同步...');

      // 更新任务状态
      task.status = TaskStatus.syncing;
      task.isRunning = true;
      await _db.updateTask(task.id, task.toMap());

      // 1. 扫描本地文件
      _reportProgress(0.05, '扫描本地文件...');
      final localSnapshots =
          await _scanner.scanLocalFolder(task, task.localPath);

      if (_isCancelled) return _finishLog(task, 'cancelled');

      // 2. 连接远端并扫描
      List<FileSnapshot> remoteSnapshots = [];
      _reportProgress(0.1, '连接远端服务器...');

      if (task.remoteProtocol == RemoteProtocol.webdav) {
        final connected = await _webdav.connect(task);
        if (!connected) throw Exception('无法连接到WebDAV服务器');
        remoteSnapshots = await _webdav.scanRemoteFolder(task);
      }

      if (_isCancelled) return _finishLog(task, 'cancelled');

      // 3. 检测变更
      _reportProgress(0.2, '检测文件变更...');
      final changes =
          await _scanner.detectChanges(task, localSnapshots, remoteSnapshots);

      _currentLog!.totalFiles = changes.length;

      if (changes.isEmpty) {
        _reportProgress(1.0, '没有文件需要同步');
        return _finishLog(task, 'success');
      }

      // 4. 执行同步操作
      int processed = 0;
      for (final change in changes) {
        if (_isCancelled) break;
        while (_isPaused) {
          await Future.delayed(Duration(milliseconds: 500));
          if (_isCancelled) break;
        }

        try {
          await _executeChange(task, change);
          _currentLog!.successCount++;
        } catch (e) {
          _currentLog!.failCount++;
          _currentLog!.entries.add(LogEntry(
            filePath: change.relativePath,
            operation: change.operation.value,
            status: 'failed',
            detail: e.toString(),
          ));

          // 重试逻辑
          bool retrySuccess = false;
          for (int i = 0; i < task.retryCount; i++) {
            await Future.delayed(Duration(seconds: task.retryDelaySeconds));
            try {
              await _executeChange(task, change);
              _currentLog!.failCount--;
              _currentLog!.successCount++;
              retrySuccess = true;
              break;
            } catch (_) {}
          }

          if (!retrySuccess && onError != null) {
            onError!('文件同步失败: ${change.relativePath} - $e');
          }
        }

        processed++;
        final progress = 0.2 + (0.7 * processed / changes.length);
        _reportProgress(progress, '同步中: $processed/${changes.length}');
      }

      // 5. 保存快照（仅在未取消时）
      if (!_isCancelled) {
        _reportProgress(0.95, '保存文件快照...');
        await _scanner.saveSnapshots(task.id, localSnapshots);

        // 6. 清理旧版本
        _reportProgress(0.98, '清理旧版本...');
        await _versionService.autoCleanup(task.id);
      }

      // 完成
      _reportProgress(1.0, '同步完成');
      return _finishLog(task, _isCancelled ? 'cancelled' : 'success');
    } catch (e) {
      _currentLog!.errorMessage = e.toString();
      if (onError != null) onError!(e.toString());
      return _finishLog(task, 'failed');
    }
  }

  /// 执行单个变更操作
  Future<void> _executeChange(SyncTask task, FileChange change) async {
    switch (change.operation) {
      case SyncOperation.upload:
        await _uploadFile(task, change);
        break;
      case SyncOperation.download:
        await _downloadFile(task, change);
        break;
      case SyncOperation.delete:
        await _deleteFile(task, change);
        break;
      case SyncOperation.conflict:
        await _handleConflict(task, change);
        break;
      case SyncOperation.skip:
        _currentLog!.skipCount++;
        break;
      case SyncOperation.rename:
        break;
    }
  }

  /// 上传文件
  Future<void> _uploadFile(SyncTask task, FileChange change) async {
    // 创建版本备份
    if (change.changeType == ChangeType.modified) {
      await _versionService.createVersion(
          task, change.localPath, change.relativePath, 'modify');
    }

    if (task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath =
          '${task.remotePath}/${change.relativePath}'.replaceAll('//', '/');
      await _webdav.uploadFile(task, change.localPath, remotePath);
    }

    _currentLog!.entries.add(LogEntry(
      filePath: change.relativePath,
      operation: 'upload',
      status: 'success',
    ));
  }

  /// 下载文件
  Future<void> _downloadFile(SyncTask task, FileChange change) async {
    final localPath = p.join(task.localPath, change.relativePath);

    // 创建版本备份
    final existingFile = File(localPath);
    if (await existingFile.exists()) {
      await _versionService.createVersion(
          task, localPath, change.relativePath, 'modify');
    }

    if (task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath =
          '${task.remotePath}/${change.relativePath}'.replaceAll('//', '/');
      await _webdav.downloadFile(task, remotePath, localPath);
    }

    _currentLog!.entries.add(LogEntry(
      filePath: change.relativePath,
      operation: 'download',
      status: 'success',
    ));
  }

  /// 删除文件
  Future<void> _deleteFile(SyncTask task, FileChange change) async {
    // 先保存版本
    if (change.localSnapshot != null) {
      await _versionService.createVersion(
          task, change.localPath, change.relativePath, 'delete');
    }

    if (task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath =
          '${task.remotePath}/${change.relativePath}'.replaceAll('//', '/');
      await _webdav.deleteRemoteFile(remotePath);
    }

    _currentLog!.entries.add(LogEntry(
      filePath: change.relativePath,
      operation: 'delete',
      status: 'success',
    ));
  }

  /// 处理冲突
  Future<void> _handleConflict(SyncTask task, FileChange change) async {
    switch (task.conflictStrategy) {
      case ConflictStrategy.localOverwrite:
        await _uploadFile(task, change);
        break;
      case ConflictStrategy.remoteOverwrite:
        await _downloadFile(task, change);
        break;
      case ConflictStrategy.keepBoth:
        // 保留双方，重命名冲突文件
        final localPath = p.join(task.localPath, change.relativePath);
        final dir = p.dirname(localPath);
        final name = p.basenameWithoutExtension(localPath);
        final ext = p.extension(localPath);
        final conflictPath = p.join(dir,
            '${name}_conflict_${DateTime.now().millisecondsSinceEpoch}$ext');

        if (task.remoteProtocol == RemoteProtocol.webdav) {
          final remotePath =
              '${task.remotePath}/${change.relativePath}'.replaceAll('//', '/');
          await _webdav.downloadFile(task, remotePath, conflictPath);
        }
        break;
    }

    _currentLog!.conflictCount++;
    _currentLog!.entries.add(LogEntry(
      filePath: change.relativePath,
      operation: 'conflict',
      status: 'resolved',
      detail: task.conflictStrategy.label,
    ));
  }

  /// 完成日志
  Future<SyncLog> _finishLog(SyncTask task, String status) async {
    _currentLog!.endTime = DateTime.now();
    _currentLog!.status = status;

    await _db.insertLog(_currentLog!.toMap());

    // 保存日志条目
    if (_currentLog!.entries.isNotEmpty) {
      final entryMaps = _currentLog!.entries.map((e) => e.toMap()).toList();
      await _db.insertLogEntries(_currentLog!.id, entryMaps);
    }

    // 更新任务状态
    task.status = status == 'success'
        ? TaskStatus.success
        : status == 'cancelled'
            ? TaskStatus.cancelled
            : TaskStatus.failed;
    task.isRunning = false;
    task.lastSyncTime = DateTime.now();
    task.syncProgress = 0.0;
    await _db.updateTask(task.id, task.toMap());

    if (onComplete != null) onComplete!(_currentLog!);

    return _currentLog!;
  }

  /// 报告进度
  void _reportProgress(double progress, String message) {
    if (onProgress != null) onProgress!(progress, message);
  }

  /// 取消同步
  void cancel() {
    _isCancelled = true;
  }

  /// 暂停同步
  void pause() {
    _isPaused = true;
  }

  /// 继续同步
  void resume() {
    _isPaused = false;
  }

  bool get isCancelled => _isCancelled;
  bool get isPaused => _isPaused;
}
