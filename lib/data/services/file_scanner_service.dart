import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../models/sync_task.dart';
import '../models/file_snapshot.dart';
import '../database/database_helper.dart';
import '../../core/utils/checksum_util.dart';

/// 文件扫描与变更检测服务
class FileScannerService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// 全量扫描本地文件夹，生成快照列表
  Future<List<FileSnapshot>> scanLocalFolder(
    SyncTask task,
    String basePath,
  ) async {
    final snapshots = <FileSnapshot>[];
    final dir = Directory(basePath);
    if (!await dir.exists()) return snapshots;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final relativePath = p.relative(entity.path, from: basePath);

      if (_shouldExclude(relativePath, task)) continue;

      if (entity is File) {
        final stat = await entity.stat();
        final crc32 = await ChecksumUtil.calculateCrc32Chunked(entity.path);
        snapshots.add(
          FileSnapshot(
            taskId: task.id,
            relativePath: relativePath.replaceAll('\\', '/'),
            absolutePath: entity.path,
            fileSize: stat.size,
            lastModified: stat.modified,
            crc32: crc32,
            isDirectory: false,
          ),
        );
      } else if (entity is Directory) {
        snapshots.add(
          FileSnapshot(
            taskId: task.id,
            relativePath: relativePath.replaceAll('\\', '/'),
            absolutePath: entity.path,
            fileSize: 0,
            lastModified: DateTime.now(),
            crc32: '',
            isDirectory: true,
          ),
        );
      }
    }
    return snapshots;
  }

  /// 检测文件变更
  Future<List<FileChange>> detectChanges(
    SyncTask task,
    List<FileSnapshot> currentLocal,
    List<FileSnapshot> currentRemote,
  ) async {
    final changes = <FileChange>[];
    final dbSnapshots = await _db.getSnapshotsByTask(task.id);

    // 构建历史快照Map
    final Map<String, FileSnapshot> historyMap = {};
    for (final s in dbSnapshots) {
      final snapshot = FileSnapshot.fromMap(s);
      historyMap[snapshot.relativePath] = snapshot;
    }

    // 构建远端快照Map
    final Map<String, FileSnapshot> remoteMap = {};
    for (final s in currentRemote) {
      remoteMap[s.relativePath] = s;
    }

    // 构建本地快照Map
    final Map<String, FileSnapshot> localMap = {};
    for (final s in currentLocal) {
      localMap[s.relativePath] = s;
    }

    // 检测本地新增和修改（目录不参与上传操作）
    for (final local in currentLocal) {
      if (local.isDirectory) continue;
      final history = historyMap[local.relativePath];
      if (history == null) {
        // 新增文件
        changes.add(
          FileChange(
            taskId: task.id,
            relativePath: local.relativePath,
            localPath: local.absolutePath,
            remotePath: '',
            changeType: ChangeType.added,
            operation: SyncOperation.upload,
            fileSize: local.fileSize,
            crc32: local.crc32,
            localSnapshot: local,
          ),
        );
      } else if (!local.isSameAs(history)) {
        // 修改文件
        changes.add(
          FileChange(
            taskId: task.id,
            relativePath: local.relativePath,
            localPath: local.absolutePath,
            remotePath: '',
            changeType: ChangeType.modified,
            operation: SyncOperation.upload,
            fileSize: local.fileSize,
            crc32: local.crc32,
            localSnapshot: local,
            remoteSnapshot: remoteMap[local.relativePath],
          ),
        );
      }
    }

    // 检测本地删除
    for (final history in historyMap.values) {
      if (!localMap.containsKey(history.relativePath) && !history.isDirectory) {
        changes.add(
          FileChange(
            taskId: task.id,
            relativePath: history.relativePath,
            localPath: history.absolutePath,
            remotePath: '',
            changeType: ChangeType.deleted,
            operation: SyncOperation.delete,
            localSnapshot: history,
          ),
        );
      }
    }

    // 检测远端变更（除仅本地模式外都按双向同步处理）
    if (task.syncDirection != SyncDirection.localOnly) {
      for (final remote in currentRemote) {
        final history = historyMap[remote.relativePath];
        if (history != null && !remote.isSameAs(history)) {
          if (localMap.containsKey(remote.relativePath)) {
            // 冲突：本地和远端都修改了
            changes.add(
              FileChange(
                taskId: task.id,
                relativePath: remote.relativePath,
                localPath: localMap[remote.relativePath]?.absolutePath ?? '',
                remotePath: remote.absolutePath,
                changeType: ChangeType.modified,
                operation: SyncOperation.conflict,
                fileSize: remote.fileSize,
                crc32: remote.crc32,
                localSnapshot: localMap[remote.relativePath],
                remoteSnapshot: remote,
              ),
            );
          } else {
            // 远端修改，本地无此文件
            changes.add(
              FileChange(
                taskId: task.id,
                relativePath: remote.relativePath,
                localPath: '',
                remotePath: remote.absolutePath,
                changeType: ChangeType.modified,
                operation: SyncOperation.download,
                fileSize: remote.fileSize,
                crc32: remote.crc32,
                remoteSnapshot: remote,
              ),
            );
          }
        }
        if (history == null && !localMap.containsKey(remote.relativePath)) {
          // 远端新增
          changes.add(
            FileChange(
              taskId: task.id,
              relativePath: remote.relativePath,
              localPath: '',
              remotePath: remote.absolutePath,
              changeType: ChangeType.added,
              operation: SyncOperation.download,
              fileSize: remote.fileSize,
              crc32: remote.crc32,
              remoteSnapshot: remote,
            ),
          );
        }
      }
    }

    return changes;
  }

  /// 保存快照到数据库
  Future<void> saveSnapshots(
    String taskId,
    List<FileSnapshot> snapshots,
  ) async {
    await _db.deleteSnapshotsByTask(taskId);
    final maps = snapshots.map((s) => s.toMap()).toList();
    await _db.insertSnapshotsBatch(maps);
  }

  /// 判断是否应排除
  bool _shouldExclude(String relativePath, SyncTask task) {
    final pathLower = relativePath.toLowerCase();

    // 排除扩展名
    for (final ext in task.excludeExtensions) {
      if (pathLower.endsWith(ext.toLowerCase())) return true;
    }

    // 排除文件夹
    final parts = relativePath.split(Platform.pathSeparator);
    for (final part in parts) {
      for (final folder in task.excludeFolders) {
        if (part.toLowerCase() == folder.toLowerCase()) return true;
      }
    }

    // 排除模式（正则）
    for (final pattern in task.excludePatterns) {
      try {
        if (RegExp(pattern).hasMatch(relativePath)) return true;
      } catch (_) {}
    }

    // 默认排除
    for (final ext in AppConstants.defaultExcludeExtensions) {
      if (pathLower.endsWith(ext)) return true;
    }
    for (final folder in AppConstants.defaultExcludeFolders) {
      if (parts.any((p) => p.toLowerCase() == folder.toLowerCase()))
        return true;
    }

    // 默认排除特定文件名
    final fileName = parts.last;
    for (final name in AppConstants.defaultExcludeFileNames) {
      if (fileName.toLowerCase() == name.toLowerCase()) return true;
    }

    return false;
  }
}
