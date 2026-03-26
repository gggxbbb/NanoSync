import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/file_version.dart';
import '../models/sync_task.dart';
import '../database/database_helper.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/checksum_util.dart';

/// 版本管理服务
class VersionService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// 获取版本存储目录路径
  String getVersionsDir(String remoteOrLocalBasePath) {
    return p.join(remoteOrLocalBasePath, AppConstants.versionsFolder);
  }

  /// 获取文件的版本存储路径
  String getVersionFilePath(
      String basePath, String relativePath, FileVersion version) {
    final versionsDir = getVersionsDir(basePath);
    final fileDir = p.dirname(relativePath);
    final versionDir = p.join(versionsDir, fileDir);
    return p.join(versionDir, version.versionName);
  }

  /// 创建文件版本（备份当前文件）
  Future<FileVersion?> createVersion(SyncTask task, String originalFilePath,
      String relativePath, String operationType) async {
    try {
      final file = File(originalFilePath);
      if (!await file.exists()) return null;

      // 获取下一个版本号
      final nextVersion =
          await _db.getLatestVersionNumber(task.id, relativePath) + 1;

      // 生成版本文件名
      final originalFileName = p.basename(relativePath);
      final versionName = FileVersion.generateVersionName(
          originalFileName, nextVersion, DateTime.now());

      // 计算CRC32
      final crc32 = await ChecksumUtil.calculateCrc32Chunked(originalFilePath);
      final fileSize = (await file.stat()).size;

      // 确定版本存储目录（在远端.versions目录下）
      final versionsDir = getVersionsDir(task.remotePath);
      final fileDir = p.dirname(relativePath);
      final versionDir = p.join(versionsDir, fileDir).replaceAll('\\', '/');
      final versionPath = p.join(versionDir, versionName).replaceAll('\\', '/');

      // 创建版本记录
      final version = FileVersion(
        taskId: task.id,
        originalPath: relativePath,
        versionPath: versionPath,
        versionName: versionName,
        versionNumber: nextVersion,
        fileSize: fileSize,
        crc32: crc32,
        operationType: operationType,
      );

      // 保存到数据库
      await _db.insertVersion(version.toMap());

      return version;
    } catch (e) {
      return null;
    }
  }

  /// 获取文件的所有版本
  Future<List<FileVersion>> getVersionsForFile(
      String taskId, String relativePath) async {
    final maps = await _db.getVersionsByPath(taskId, relativePath);
    return maps.map((m) => FileVersion.fromMap(m)).toList();
  }

  /// 获取任务的所有版本
  Future<List<FileVersion>> getVersionsForTask(String taskId) async {
    final maps = await _db.getVersionsByTask(taskId);
    return maps.map((m) => FileVersion.fromMap(m)).toList();
  }

  /// 恢复指定版本
  Future<bool> restoreVersion(FileVersion version, String targetPath) async {
    try {
      final sourceFile = File(version.versionPath);
      if (!await sourceFile.exists()) return false;

      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 删除指定版本
  Future<bool> deleteVersion(FileVersion version) async {
    try {
      await _db.deleteVersion(version.id);
      final file = File(version.versionPath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 批量删除版本
  Future<int> batchDeleteVersions(List<String> versionIds) async {
    int deleted = 0;
    for (final id in versionIds) {
      try {
        await _db.deleteVersion(id);
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  /// 自动清理旧版本
  Future<int> autoCleanup(String taskId,
      {int? maxVersions, int? maxDays, int? maxSizeGB}) async {
    int totalDeleted = 0;
    final maxVer = maxVersions ?? AppConstants.defaultMaxVersions;
    final maxD = maxDays ?? AppConstants.defaultMaxVersionDays;

    // 清理超出数量限制的版本
    final versions = await getVersionsForTask(taskId);

    // 按原始文件路径分组
    final Map<String, List<FileVersion>> grouped = {};
    for (final v in versions) {
      grouped.putIfAbsent(v.originalPath, () => []).add(v);
    }

    for (final entry in grouped.entries) {
      final fileVersions = entry.value;
      fileVersions.sort((a, b) => b.versionNumber.compareTo(a.versionNumber));

      // 删除超出数量限制的
      if (fileVersions.length > maxVer) {
        for (final v in fileVersions.sublist(maxVer)) {
          if (await deleteVersion(v)) totalDeleted++;
        }
      }
    }

    // 清理超出时间限制的版本
    final cutoffDate = DateTime.now().subtract(Duration(days: maxD));
    totalDeleted += await _db.deleteVersionsOlderThan(taskId, cutoffDate);

    return totalDeleted;
  }

  /// 获取版本总大小
  Future<int> getTotalVersionSize(String taskId) async {
    final versions = await getVersionsForTask(taskId);
    int total = 0;
    for (final v in versions) {
      total += v.fileSize;
    }
    return total;
  }

  /// 按相对路径获取所有唯一文件路径
  Future<List<String>> getUniqueFilePaths(String taskId) async {
    final versions = await getVersionsForTask(taskId);
    final paths = versions.map((v) => v.originalPath).toSet().toList();
    paths.sort();
    return paths;
  }
}
