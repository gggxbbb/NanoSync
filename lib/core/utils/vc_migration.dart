import 'dart:io';
import 'package:path/path.dart' as p;
import '../../data/database/database_helper.dart';
import '../../data/models/vc_models.dart';
import '../../data/services/vc_engine.dart';
import '../../data/vc_database.dart';
import 'checksum_util.dart';

class VcMigrationProgress {
  final int processed;
  final int total;
  final String currentTask;
  final String currentFile;
  final String message;

  VcMigrationProgress({
    required this.processed,
    required this.total,
    this.currentTask = '',
    this.currentFile = '',
    this.message = '',
  });

  double get percent => total == 0 ? 1.0 : processed / total;
}

class VcMigrationResult {
  final bool success;
  final String message;
  final int totalLegacyVersions;
  final int migratedVersions;
  final int skippedVersions;
  final int migratedRepositories;
  final int skippedRepositories;

  VcMigrationResult({
    required this.success,
    required this.message,
    this.totalLegacyVersions = 0,
    this.migratedVersions = 0,
    this.skippedVersions = 0,
    this.migratedRepositories = 0,
    this.skippedRepositories = 0,
  });
}

class _MigratedFileState {
  final String hash;
  final int size;

  _MigratedFileState(this.hash, this.size);
}

class VcMigration {
  final DatabaseHelper _legacyDbHelper;
  final VcDatabase _vcDb;

  VcMigration({DatabaseHelper? legacyDbHelper, VcDatabase? vcDb})
    : _legacyDbHelper = legacyDbHelper ?? DatabaseHelper.instance,
      _vcDb = vcDb ?? VcDatabase.instance;

  Future<bool> hasLegacyVersionTable() async {
    final db = await _legacyDbHelper.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='file_versions'",
    );
    return tables.isNotEmpty;
  }

  Future<VcMigrationResult> migrateLegacyVersions({
    bool dropLegacyTableAfterMigration = false,
    bool skipIfRepositoryHasCommits = true,
    void Function(VcMigrationProgress progress)? onProgress,
  }) async {
    try {
      final legacyDb = await _legacyDbHelper.database;
      if (!await hasLegacyVersionTable()) {
        return VcMigrationResult(
          success: true,
          message: '未发现 file_versions 表，无需迁移',
        );
      }

      final allLegacyVersions = await legacyDb.query(
        'file_versions',
        orderBy: 'task_id ASC, created_at ASC, version_number ASC',
      );

      if (allLegacyVersions.isEmpty) {
        return VcMigrationResult(success: true, message: '旧版本表为空，无需迁移');
      }

      final tasks = await _legacyDbHelper.getAllTasks();
      final taskById = <String, Map<String, dynamic>>{};
      for (final task in tasks) {
        final taskId = _asString(task['id']);
        if (taskId.isNotEmpty) {
          taskById[taskId] = task;
        }
      }

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in allLegacyVersions) {
        final taskId = _asString(row['task_id']);
        if (taskId.isEmpty) {
          continue;
        }
        grouped.putIfAbsent(taskId, () => <Map<String, dynamic>>[]).add(row);
      }

      final repoCache = await _vcDb.getAllRepositories();
      var processed = 0;
      var migratedVersions = 0;
      var skippedVersions = 0;
      var migratedRepositories = 0;
      var skippedRepositories = 0;

      for (final entry in grouped.entries) {
        final taskId = entry.key;
        final rows = entry.value;
        final task = taskById[taskId];

        if (task == null) {
          skippedRepositories++;
          processed += rows.length;
          continue;
        }

        final taskName = _asString(task['name']);
        final localPath = _asString(task['local_path']);
        if (localPath.isEmpty) {
          skippedRepositories++;
          processed += rows.length;
          continue;
        }

        final repo = await _ensureRepository(
          repoCache: repoCache,
          taskName: taskName.isEmpty ? 'Migrated-$taskId' : taskName,
          localPath: localPath,
        );

        if (skipIfRepositoryHasCommits && repo.headCommitId.isNotEmpty) {
          skippedRepositories++;
          processed += rows.length;
          continue;
        }

        final branch = await _resolveCurrentBranch(repo);
        if (branch == null) {
          skippedRepositories++;
          processed += rows.length;
          continue;
        }

        var parentCommitId = repo.headCommitId;
        final stateByPath = <String, _MigratedFileState>{};
        var taskMigratedCount = 0;

        for (final row in rows) {
          processed++;

          final relativePath = _asString(row['original_path']);
          final versionPath = _asString(row['version_path']);
          final versionNumber = _asInt(row['version_number']);
          final operationType = _asString(row['operation_type']);
          final createdAt = _parseDate(row['created_at']);

          onProgress?.call(
            VcMigrationProgress(
              processed: processed,
              total: allLegacyVersions.length,
              currentTask: taskName,
              currentFile: relativePath,
              message: '迁移版本 v$versionNumber',
            ),
          );

          if (relativePath.isEmpty || versionPath.isEmpty) {
            skippedVersions++;
            continue;
          }

          final legacyFile = File(versionPath);
          if (!await legacyFile.exists()) {
            skippedVersions++;
            continue;
          }

          var hash = _asString(row['crc32']);
          if (hash.isEmpty) {
            hash = await ChecksumUtil.calculateCrc32Chunked(versionPath);
          }
          if (hash.isEmpty) {
            hash = createdAt.microsecondsSinceEpoch.toRadixString(36);
          }

          var size = _asInt(row['file_size']);
          if (size <= 0) {
            size = (await legacyFile.stat()).size;
          }

          final objectPath = p.join(localPath, '.nanosync', 'objects', hash);
          final objectFile = File(objectPath);
          if (!await objectFile.exists()) {
            await objectFile.parent.create(recursive: true);
            await legacyFile.copy(objectPath);
          }

          final previous = stateByPath[relativePath];
          final changeType = previous == null
              ? VcChangeType.added
              : VcChangeType.modified;
          final oldSize = previous?.size ?? 0;
          final oldHash = previous?.hash ?? '';
          final additions = size > oldSize ? size - oldSize : 0;
          final deletions = oldSize > size ? oldSize - size : 0;

          final commit = VcCommit(
            repositoryId: repo.id,
            branchId: branch.id,
            parentCommitId: parentCommitId,
            message:
                'Migrate legacy version: $relativePath (v$versionNumber${operationType.isEmpty ? '' : ', $operationType'})',
            authorName: 'NanoSync Migration',
            authorEmail: 'migration@nanosync.local',
            committerName: 'NanoSync Migration',
            committerEmail: 'migration@nanosync.local',
            authoredAt: createdAt,
            committedAt: createdAt,
            fileCount: 1,
            additions: additions,
            deletions: deletions,
          );
          await _vcDb.insertCommit(commit.toMap());

          final treeEntry = VcTreeEntry(
            commitId: commit.id,
            relativePath: relativePath,
            fileSize: size,
            fileHash: hash,
            createdAt: createdAt,
          );
          await _vcDb.insertTreeEntry(treeEntry.toMap());

          final fileChange = VcFileChange(
            repositoryId: repo.id,
            commitId: commit.id,
            relativePath: relativePath,
            changeType: changeType,
            status: VcFileStatus.committed,
            oldSize: oldSize,
            newSize: size,
            oldHash: oldHash,
            newHash: hash,
            additions: additions,
            deletions: deletions,
            createdAt: createdAt,
          );
          await _vcDb.insertFileChange(fileChange.toMap());

          parentCommitId = commit.id;
          stateByPath[relativePath] = _MigratedFileState(hash, size);
          migratedVersions++;
          taskMigratedCount++;
        }

        if (taskMigratedCount > 0) {
          await _vcDb.updateBranch(branch.id, {'commit_id': parentCommitId});
          await _vcDb.updateRepository(repo.id, {
            'head_commit_id': parentCommitId,
            'updated_at': DateTime.now().toIso8601String(),
          });
          migratedRepositories++;
        } else {
          skippedRepositories++;
        }
      }

      if (dropLegacyTableAfterMigration) {
        await legacyDb.execute('DROP TABLE IF EXISTS file_versions');
        await legacyDb.execute('DROP INDEX IF EXISTS idx_versions_task_id');
        await legacyDb.execute(
          'DROP INDEX IF EXISTS idx_versions_original_path',
        );
      }

      return VcMigrationResult(
        success: true,
        message: '迁移完成',
        totalLegacyVersions: allLegacyVersions.length,
        migratedVersions: migratedVersions,
        skippedVersions: skippedVersions,
        migratedRepositories: migratedRepositories,
        skippedRepositories: skippedRepositories,
      );
    } catch (e) {
      return VcMigrationResult(success: false, message: '迁移失败: $e');
    }
  }

  Future<VcRepository> _ensureRepository({
    required List<VcRepository> repoCache,
    required String taskName,
    required String localPath,
  }) async {
    VcRepository? repo;
    for (final item in repoCache) {
      if (item.localPath == localPath) {
        repo = item;
        break;
      }
    }

    if (repo == null) {
      repo = VcRepository(name: taskName, localPath: localPath);
      await _vcDb.insertRepository(repo.toMap());
      repoCache.add(repo);
    }

    if (!repo.isInitialized) {
      final engine = VcEngine(repositoryId: repo.id);
      await engine.init(name: 'main');
      final refreshed = await _vcDb.getRepository(repo.id);
      if (refreshed != null) {
        repo = refreshed;
        final index = repoCache.indexWhere((r) => r.id == repo!.id);
        if (index >= 0) {
          repoCache[index] = repo;
        }
      }
    }

    return repo;
  }

  Future<VcBranch?> _resolveCurrentBranch(VcRepository repo) async {
    if (repo.currentBranchId.isNotEmpty) {
      final branch = await _vcDb.getBranch(repo.currentBranchId);
      if (branch != null) {
        return branch;
      }
    }

    final branches = await _vcDb.getBranches(repo.id);
    if (branches.isEmpty) {
      return null;
    }
    return branches.first;
  }

  String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
