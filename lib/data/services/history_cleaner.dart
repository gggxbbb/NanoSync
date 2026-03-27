import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/history_config.dart';
import '../models/sync_result.dart';
import '../models/vc_models.dart';
import '../vc_database.dart';
import 'repository_manager.dart';

class HistoryCleaner {
  static HistoryCleaner? _instance;
  final VcDatabase _vcDb;
  final RepositoryManager _repoManager;

  HistoryCleaner._({VcDatabase? vcDb, RepositoryManager? repoManager})
    : _vcDb = vcDb ?? VcDatabase.instance,
      _repoManager = repoManager ?? RepositoryManager.instance;

  static HistoryCleaner get instance {
    _instance ??= HistoryCleaner._();
    return _instance!;
  }

  Future<HistoryStats> calculateStats(Repository repo) async {
    final commits = await _vcDb.getCommits(repo.id);
    int commitCount = commits.length;

    int oldestCommitAge = 0;
    if (commits.isNotEmpty) {
      final oldest = commits.last;
      final oldestDate = oldest.committedAt;
      final now = DateTime.now();
      oldestCommitAge = now.difference(oldestDate).inDays;
    }

    final objectsDir = p.join(repo.localPath, '.nanosync', 'objects');
    int objectsSizeBytes = 0;
    int objectsCount = 0;

    if (await Directory(objectsDir).exists()) {
      await for (final entity in Directory(objectsDir).list()) {
        if (entity is File) {
          try {
            objectsSizeBytes += await entity.length();
            objectsCount++;
          } catch (_) {}
        }
      }
    }

    return HistoryStats(
      commitCount: commitCount,
      oldestCommitAge: oldestCommitAge,
      objectsSizeMb: (objectsSizeBytes / (1024 * 1024)).round(),
      objectsCount: objectsCount,
    );
  }

  bool needsCleanup(HistoryConfig config, HistoryStats stats) {
    return config.shouldCleanup(
      commitCount: stats.commitCount,
      oldestCommitAge: stats.oldestCommitAge,
      objectsSizeMb: stats.objectsSizeMb,
    );
  }

  Future<CleanupResult> cleanup(Repository repo) async {
    try {
      final config = repo.config;
      if (config == null) {
        return const CleanupResult(error: 'Repository config not found');
      }

      final stats = await calculateStats(repo);
      if (!needsCleanup(config.history, stats)) {
        return const CleanupResult(success: true);
      }

      final commits = await _vcDb.getCommits(repo.id);
      if (commits.isEmpty) {
        return const CleanupResult(success: true);
      }

      final commitsToKeep = _selectCommitsToKeep(commits, config.history);
      final commitsToDelete = commits
          .where((c) => !commitsToKeep.contains(c.id))
          .toList();

      int deletedCommits = 0;
      final referencedHashes = <String>{};

      for (final commitId in commitsToKeep) {
        final treeEntries = await _vcDb.getTreeEntries(commitId);
        for (final entry in treeEntries) {
          if (entry.fileHash.isNotEmpty) {
            referencedHashes.add(entry.fileHash);
          }
        }
      }

      for (final commit in commitsToDelete) {
        await _deleteCommitData(commit.id);
        deletedCommits++;
      }

      int deletedObjects = await _cleanupUnreferencedObjects(
        repo,
        referencedHashes,
      );

      return CleanupResult(
        deletedCommits: deletedCommits,
        deletedObjects: deletedObjects,
        freedSizeMb: 0,
        success: true,
      );
    } catch (e) {
      return CleanupResult(error: e.toString());
    }
  }

  Set<String> _selectCommitsToKeep(
    List<VcCommit> commits,
    HistoryConfig config,
  ) {
    final toKeep = <String>{};
    final now = DateTime.now();

    if (config.maxCount > 0 && commits.length > config.maxCount) {
      for (int i = 0; i < config.maxCount && i < commits.length; i++) {
        toKeep.add(commits[i].id);
      }
    } else {
      for (final commit in commits) {
        if (config.maxDays > 0) {
          final age = now.difference(commit.committedAt).inDays;
          if (age <= config.maxDays) {
            toKeep.add(commit.id);
          }
        } else {
          toKeep.add(commit.id);
        }
      }
    }

    if (toKeep.isEmpty && commits.isNotEmpty) {
      toKeep.add(commits.first.id);
    }

    return toKeep;
  }

  Future<void> _deleteCommitData(String commitId) async {
    final db = await _vcDb.database;
    await db.delete(
      'vc_file_changes',
      where: 'commit_id = ?',
      whereArgs: [commitId],
    );
    await db.delete(
      'vc_tree_entries',
      where: 'commit_id = ?',
      whereArgs: [commitId],
    );
    await db.delete('vc_commits', where: 'id = ?', whereArgs: [commitId]);
  }

  Future<int> _cleanupUnreferencedObjects(
    Repository repo,
    Set<String> referencedHashes,
  ) async {
    final objectsDir = p.join(repo.localPath, '.nanosync', 'objects');
    if (!await Directory(objectsDir).exists()) {
      return 0;
    }

    int deletedCount = 0;
    await for (final entity in Directory(objectsDir).list()) {
      if (entity is File) {
        final hash = p.basename(entity.path);
        if (!referencedHashes.contains(hash)) {
          try {
            await entity.delete();
            deletedCount++;
          } catch (_) {}
        }
      }
    }

    return deletedCount;
  }
}
