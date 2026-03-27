import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/sync_task.dart';
import '../models/file_snapshot.dart';
import '../models/sync_log.dart';
import '../database/database_helper.dart';
import '../../core/constants/enums.dart';
import 'file_scanner_service.dart';
import 'smb_service.dart';
import 'vc_sync_service.dart';
import 'webdav_service.dart';
import '../vc_database.dart';
import 'vc_engine.dart';

/// 同步引擎 - 核心同步逻辑
class SyncEngine {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FileScannerService _scanner = FileScannerService();
  final WebDAVService _webdav = WebDAVService();
  final SmbService _smb = SmbService();
  final VcSyncService _vcSync = VcSyncService();

  /// 同步进度回调
  final void Function(double progress, String message)? onProgress;

  /// 同步完成回调
  final void Function(SyncLog log)? onComplete;

  /// 同步错误回调
  final void Function(String error)? onError;

  bool _isCancelled = false;
  bool _isPaused = false;
  SyncLog? _currentLog;
  String _vcRepositoryId = '';
  String _vcRemoteId = '';
  String _preSyncCommitId = '';
  String _postSyncCommitId = '';
  String _remoteHeadCommitId = '';
  int _aheadCount = 0;
  int _behindCount = 0;

  SyncEngine({this.onProgress, this.onComplete, this.onError});

  /// 执行同步任务
  Future<SyncLog?> executeSync(SyncTask task) async {
    _isCancelled = false;
    _isPaused = false;
    _vcRepositoryId = '';
    _vcRemoteId = '';
    _preSyncCommitId = '';
    _postSyncCommitId = '';
    _remoteHeadCommitId = '';
    _aheadCount = 0;
    _behindCount = 0;

    final effectiveTask = await _resolveTaskWithTarget(task);

    await _prepareVcContext(effectiveTask);
    _preSyncCommitId = await _autoCommit(
      message:
          'sync(pre): ${effectiveTask.name} -> ${effectiveTask.remoteProtocol.value}:${effectiveTask.remoteHost}${effectiveTask.remotePath}',
    );
    await _prepareVcStateBeforeSync(effectiveTask);

    _currentLog = SyncLog(taskId: task.id, taskName: task.name);

    try {
      _reportProgress(0.0, '开始同步...');

      // 更新任务状态
      task.status = TaskStatus.syncing;
      task.isRunning = true;
      await _db.updateTask(task.id, task.toMap());

      // 1. 扫描本地文件
      _reportProgress(0.05, '扫描本地文件...');
      final localSnapshots = await _scanner.scanLocalFolder(
        effectiveTask,
        effectiveTask.localPath,
      );

      if (_isCancelled) return _finishLog(task, 'cancelled');

      // 2. 连接远端并扫描
      List<FileSnapshot> remoteSnapshots = [];
      if (effectiveTask.syncDirection != SyncDirection.localOnly) {
        _reportProgress(0.1, '连接远端服务器...');

        if (effectiveTask.remoteProtocol == RemoteProtocol.webdav) {
          final connected = await _webdav.connect(effectiveTask);
          if (!connected) throw Exception('无法连接到WebDAV服务器');
          remoteSnapshots = await _webdav.scanRemoteFolder(effectiveTask);
        } else if (effectiveTask.remoteProtocol == RemoteProtocol.smb) {
          final connected = await _smb.connect(effectiveTask);
          if (!connected) throw Exception('无法连接到 SMB 服务器');
          remoteSnapshots = await _smb.scanRemoteFolder(effectiveTask);
        }
      }

      if (_isCancelled) return _finishLog(task, 'cancelled');

      // 3. 检测变更
      _reportProgress(0.2, '检测文件变更...');
      final changes = await _scanner.detectChanges(
        effectiveTask,
        localSnapshots,
        remoteSnapshots,
      );

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
          await _executeChange(effectiveTask, change);
          _currentLog!.successCount++;
        } catch (e) {
          _currentLog!.failCount++;
          _currentLog!.entries.add(
            LogEntry(
              filePath: change.relativePath,
              operation: change.operation.value,
              status: 'failed',
              detail: e.toString(),
            ),
          );

          // 重试逻辑
          bool retrySuccess = false;
          for (int i = 0; i < task.retryCount; i++) {
            await Future.delayed(Duration(seconds: task.retryDelaySeconds));
            try {
              await _executeChange(effectiveTask, change);
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
        await _finalizeVcStateAfterSync(effectiveTask);
        _postSyncCommitId = await _autoCommit(
          message:
              'sync(post): ${effectiveTask.name} -> ${effectiveTask.remoteProtocol.value}:${effectiveTask.remoteHost}${effectiveTask.remotePath}',
        );
        await _prepareVcStateBeforeSync(effectiveTask);

        _reportProgress(0.95, '保存文件快照...');
        final latestLocalSnapshots = await _scanner.scanLocalFolder(
          effectiveTask,
          effectiveTask.localPath,
        );
        await _scanner.saveSnapshots(effectiveTask.id, latestLocalSnapshots);
      }

      // 完成
      _reportProgress(1.0, '同步完成');
      return _finishLog(task, _isCancelled ? 'cancelled' : 'success');
    } catch (e) {
      _currentLog!.errorMessage = e.toString();
      if (onError != null) onError!(e.toString());
      return _finishLog(task, 'failed');
    } finally {
      _webdav.disconnect();
      await _smb.disconnect();
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
    if (task.syncDirection != SyncDirection.localOnly &&
        task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _webdav.uploadFile(task, change.localPath, remotePath);
    } else if (task.syncDirection != SyncDirection.localOnly &&
        task.remoteProtocol == RemoteProtocol.smb) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _smb.uploadFile(task, change.localPath, remotePath);
    }

    if (task.syncDirection == SyncDirection.localOnly) {
      _currentLog!.skipCount++;
    }

    _currentLog!.entries.add(
      LogEntry(
        filePath: change.relativePath,
        operation: task.syncDirection == SyncDirection.localOnly
            ? 'skip'
            : 'upload',
        status: 'success',
      ),
    );
  }

  /// 下载文件
  Future<void> _downloadFile(SyncTask task, FileChange change) async {
    final localPath = p.join(task.localPath, change.relativePath);

    if (task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _webdav.downloadFile(task, remotePath, localPath);
    } else if (task.remoteProtocol == RemoteProtocol.smb) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _smb.downloadFile(task, remotePath, localPath);
    }

    _currentLog!.entries.add(
      LogEntry(
        filePath: change.relativePath,
        operation: 'download',
        status: 'success',
      ),
    );
  }

  /// 删除文件
  Future<void> _deleteFile(SyncTask task, FileChange change) async {
    if (task.syncDirection != SyncDirection.localOnly &&
        task.remoteProtocol == RemoteProtocol.webdav) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _webdav.deleteRemoteFile(remotePath);
    } else if (task.syncDirection != SyncDirection.localOnly &&
        task.remoteProtocol == RemoteProtocol.smb) {
      final remotePath = '${task.remotePath}/${change.relativePath}'.replaceAll(
        '//',
        '/',
      );
      await _smb.deleteRemoteFile(task, remotePath);
    }

    _currentLog!.entries.add(
      LogEntry(
        filePath: change.relativePath,
        operation: 'delete',
        status: 'success',
      ),
    );
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
        final merged = await _tryThreeWayMerge(task, change);
        if (merged) {
          break;
        }

        // 保留双方，重命名冲突文件
        final localPath = p.join(task.localPath, change.relativePath);
        final dir = p.dirname(localPath);
        final name = p.basenameWithoutExtension(localPath);
        final ext = p.extension(localPath);
        final conflictPath = p.join(
          dir,
          '${name}_conflict_${DateTime.now().millisecondsSinceEpoch}$ext',
        );

        if (task.remoteProtocol == RemoteProtocol.webdav) {
          final remotePath = '${task.remotePath}/${change.relativePath}'
              .replaceAll('//', '/');
          await _webdav.downloadFile(task, remotePath, conflictPath);
        } else if (task.remoteProtocol == RemoteProtocol.smb) {
          final remotePath = '${task.remotePath}/${change.relativePath}'
              .replaceAll('//', '/');
          await _smb.downloadFile(task, remotePath, conflictPath);
        }
        break;
    }

    _currentLog!.conflictCount++;
    _currentLog!.entries.add(
      LogEntry(
        filePath: change.relativePath,
        operation: 'conflict',
        status: 'resolved',
        detail: task.conflictStrategy.label,
      ),
    );
  }

  /// 完成日志
  Future<SyncLog> _finishLog(SyncTask task, String status) async {
    _currentLog!.endTime = DateTime.now();
    _currentLog!.status = status;

    final repo = _vcRepositoryId.isEmpty
        ? await VcDatabase.instance.getRepositoryByLocalPath(task.localPath)
        : await VcDatabase.instance.getRepository(_vcRepositoryId);

    if (repo != null) {
      _vcRepositoryId = repo.id;
      if (_remoteHeadCommitId.isNotEmpty && _vcRemoteId.isNotEmpty) {
        final aheadBehind = await _vcSync.computeAheadBehind(
          repositoryId: repo.id,
          remoteHeadCommitId: _remoteHeadCommitId,
        );
        _aheadCount = aheadBehind.$1;
        _behindCount = aheadBehind.$2;
        await _vcSync.updateRemoteHeads(
          remoteId: _vcRemoteId,
          localHeadCommitId: repo.headCommitId,
          remoteHeadCommitId: _remoteHeadCommitId,
        );
      }

      await _vcSync.recordSyncRecord(
        repositoryId: repo.id,
        remoteId: _vcRemoteId.isEmpty ? null : _vcRemoteId,
        task: task,
        log: _currentLog!,
        preCommitId: _preSyncCommitId,
        postCommitId: _postSyncCommitId,
        remoteHeadCommitId: _remoteHeadCommitId,
        localHeadCommitId: repo.headCommitId,
        aheadCount: _aheadCount,
        behindCount: _behindCount,
      );
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

  Future<SyncTask> _resolveTaskWithTarget(SyncTask task) async {
    if (task.syncDirection == SyncDirection.localOnly) {
      return task;
    }

    if (task.targetId == null || task.targetId!.isEmpty) {
      return task;
    }

    final targetMap = await _db.getTarget(task.targetId!);
    if (targetMap == null) {
      throw Exception('同步目标不存在或已删除，请重新选择目标');
    }

    return task.copyWith(
      remoteProtocol: RemoteProtocol.fromValue(
        targetMap['remote_protocol'] as String,
      ),
      remoteHost: targetMap['remote_host'] as String,
      remotePort: targetMap['remote_port'] as int? ?? 445,
      remoteUsername: targetMap['remote_username'] as String? ?? '',
      remotePassword: targetMap['remote_password'] as String? ?? '',
    );
  }

  Future<void> _prepareVcStateBeforeSync(SyncTask task) async {
    try {
      await _vcSync.exportRepositoryState(task.localPath);
    } catch (_) {
      // Keep sync available even if repository metadata export fails.
    }
  }

  Future<void> _finalizeVcStateAfterSync(SyncTask task) async {
    if (task.syncDirection == SyncDirection.localOnly) {
      return;
    }
    try {
      final result = await _vcSync.importRepositoryState(task.localPath);
      if (result.imported) {
        _remoteHeadCommitId = result.remoteHeadCommitId;
        await _vcSync.exportRepositoryState(task.localPath);
      }
    } catch (_) {
      // Keep sync available even if repository metadata import fails.
    }
  }

  Future<void> _prepareVcContext(SyncTask task) async {
    final repo = await _vcSync.ensureRepositoryForLocalPath(
      localPath: task.localPath,
      preferredName: task.name,
    );
    _vcRepositoryId = repo.id;

    if (task.syncDirection == SyncDirection.localOnly) {
      return;
    }

    String? targetName;
    if (task.targetId != null && task.targetId!.isNotEmpty) {
      final targetMap = await _db.getTarget(task.targetId!);
      targetName = targetMap?['name']?.toString();
    }

    final remote = await _vcSync.ensureRemoteForTask(
      repositoryId: repo.id,
      task: task,
      targetName: targetName,
    );
    _vcRemoteId = remote['id']?.toString() ?? '';
  }

  Future<String> _autoCommit({required String message}) async {
    if (_vcRepositoryId.isEmpty) {
      return '';
    }

    try {
      final engine = VcEngine(repositoryId: _vcRepositoryId);
      final addResult = await engine.add(all: true);
      if (addResult.result == VcOperationResult.error) {
        return '';
      }

      final commitResult = await engine.commit(message: message);
      if (!commitResult.isSuccess) {
        return '';
      }

      final data = commitResult.data;
      if (data == null) {
        return '';
      }

      final commitId = (data as dynamic).id;
      return commitId == null ? '' : commitId.toString();
    } catch (_) {
      return '';
    }
  }

  Future<bool> _tryThreeWayMerge(SyncTask task, FileChange change) async {
    if (_vcRepositoryId.isEmpty) {
      return false;
    }

    try {
      final repo = await VcDatabase.instance.getRepository(_vcRepositoryId);
      if (repo == null || repo.headCommitId.isEmpty) {
        return false;
      }

      final entries = await VcDatabase.instance.getTreeEntries(
        repo.headCommitId,
      );
      dynamic baseEntry;
      for (final entry in entries) {
        if (entry.relativePath == change.relativePath) {
          baseEntry = entry;
          break;
        }
      }
      if (baseEntry == null || (baseEntry.fileHash as String).isEmpty) {
        return false;
      }

      final basePath = p.join(
        repo.localPath,
        '.nanosync',
        'objects',
        baseEntry.fileHash as String,
      );
      final localPath = p.join(task.localPath, change.relativePath);

      final baseFile = File(basePath);
      final localFile = File(localPath);
      if (!await baseFile.exists() || !await localFile.exists()) {
        return false;
      }

      final tempDir = await Directory.systemTemp.createTemp('nanosync-merge-');
      final remoteTempPath = p.join(tempDir.path, 'remote.tmp');

      try {
        final remotePath = '${task.remotePath}/${change.relativePath}'
            .replaceAll('//', '/');
        if (task.remoteProtocol == RemoteProtocol.webdav) {
          await _webdav.downloadFile(task, remotePath, remoteTempPath);
        } else if (task.remoteProtocol == RemoteProtocol.smb) {
          await _smb.downloadFile(task, remotePath, remoteTempPath);
        } else {
          return false;
        }

        final baseText = await baseFile.readAsString();
        final localText = await localFile.readAsString();
        final remoteText = await File(remoteTempPath).readAsString();
        final merged = _simpleThreeWayMerge(baseText, localText, remoteText);
        if (merged == null) {
          return false;
        }

        await localFile.writeAsString(merged);
        await _uploadFile(
          task,
          FileChange(
            taskId: change.taskId,
            relativePath: change.relativePath,
            localPath: localPath,
            remotePath: change.remotePath,
            changeType: ChangeType.modified,
            operation: SyncOperation.upload,
            fileSize: change.fileSize,
            crc32: change.crc32,
          ),
        );

        _currentLog!.entries.add(
          LogEntry(
            filePath: change.relativePath,
            operation: 'merge',
            status: 'resolved',
            detail: '三方合并自动完成',
          ),
        );
        return true;
      } finally {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {
      return false;
    }
  }

  String? _simpleThreeWayMerge(String base, String local, String remote) {
    if (local == remote) {
      return local;
    }
    if (local == base) {
      return remote;
    }
    if (remote == base) {
      return local;
    }
    return null;
  }
}
