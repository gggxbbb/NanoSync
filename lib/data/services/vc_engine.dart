import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/vc_models.dart';
import '../vc_database.dart';
import '../../core/utils/checksum_util.dart';
import '../../core/utils/binary_optimization.dart';

enum VcOperationResult {
  success,
  nothingToCommit,
  conflict,
  error,
  notInitialized,
  branchExists,
  branchNotFound,
  uncommittedChanges,
}

enum VcConflictResolutionStrategy { ours, theirs, manual }

class VcConflictFile {
  final String relativePath;
  final int markerBlocks;
  final bool isStaged;

  VcConflictFile({
    required this.relativePath,
    required this.markerBlocks,
    this.isStaged = false,
  });
}

class VcOperationResultData {
  final VcOperationResult result;
  final String message;
  final dynamic data;

  VcOperationResultData({required this.result, this.message = '', this.data});

  bool get isSuccess => result == VcOperationResult.success;
}

class VcRepositoryStatus {
  final String branchName;
  final String headCommitId;
  final int stagedCount;
  final int unstagedCount;
  final int untrackedCount;
  final int ahead;
  final int behind;
  final bool isClean;
  final bool isInitialized;

  VcRepositoryStatus({
    this.branchName = 'main',
    this.headCommitId = '',
    this.stagedCount = 0,
    this.unstagedCount = 0,
    this.untrackedCount = 0,
    this.ahead = 0,
    this.behind = 0,
    this.isClean = true,
    this.isInitialized = false,
  });
}

class VcDiffLine {
  final int oldLineNumber;
  final int newLineNumber;
  final String content;
  final String type;

  VcDiffLine({
    required this.oldLineNumber,
    required this.newLineNumber,
    required this.content,
    required this.type,
  });
}

class VcDiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<VcDiffLine> lines;

  VcDiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });
}

class VcFileDiff {
  final String relativePath;
  final String oldPath;
  final VcChangeType changeType;
  final List<VcDiffHunk> hunks;
  final int additions;
  final int deletions;
  final bool isBinary;

  VcFileDiff({
    required this.relativePath,
    this.oldPath = '',
    required this.changeType,
    this.hunks = const [],
    this.additions = 0,
    this.deletions = 0,
    this.isBinary = false,
  });
}

class VcEngine {
  final VcDatabase _db;
  final String repositoryId;

  VcEngine({required this.repositoryId, VcDatabase? db})
    : _db = db ?? VcDatabase.instance;

  String get _versionsDir => '.nanosync/objects';
  String get _stagingDir => '.nanosync/staging';
  String get _ignoreFileName => '.nanosyncignore';

  static const List<String> _defaultIgnoreRules = [
    '.nanosync/',
    '.git/',
    'Thumbs.db',
    '.DS_Store',
  ];

  Future<VcRepository?> _getRepository() async {
    return await _db.getRepository(repositoryId);
  }

  Future<void> _ensureInitialized() async {
    final repo = await _getRepository();
    if (repo == null || !repo.isInitialized) {
      throw StateError('Repository not initialized');
    }
  }

  Future<VcOperationResultData> init({
    String name = 'main',
    List<String> ignoreRules = const [],
  }) async {
    try {
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      if (repo.isInitialized) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository already initialized',
        );
      }

      final branch = VcBranch(
        repositoryId: repositoryId,
        name: name,
        isDefault: true,
      );

      await _db.insertBranch(branch.toMap());

      await _db.updateRepository(repositoryId, {
        'current_branch_id': branch.id,
        'is_initialized': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final repoDir = Directory(p.join(repo.localPath, '.nanosync'));
      await repoDir.create(recursive: true);
      await Directory(
        p.join(repo.localPath, _versionsDir),
      ).create(recursive: true);
      await Directory(
        p.join(repo.localPath, _stagingDir),
      ).create(recursive: true);

      await _writeIgnoreRules(repo.localPath, ignoreRules);

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Initialized empty repository',
        data: branch,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to initialize repository: $e',
      );
    }
  }

  Future<VcOperationResultData> status() async {
    try {
      final repo = await _getRepository();
      if (repo == null || !repo.isInitialized) {
        return VcOperationResultData(
          result: VcOperationResult.notInitialized,
          message: 'Repository not initialized',
          data: VcRepositoryStatus(isInitialized: false),
        );
      }

      final branch = await _db.getBranch(repo.currentBranchId);
      final stagingEntries = await _db.getStagingEntries(repositoryId);
      final workingChanges = await _scanWorkingDirectory(repo);

      final stagedCount = stagingEntries.where((e) => e.isStaged).length;
      final unstagedCount = stagingEntries.where((e) => !e.isStaged).length;
      final untrackedCount = workingChanges
          .where((c) => c.status == VcFileStatus.untracked)
          .length;

      final remoteHeadCommitId = await _selectLatestRemoteHeadCommitId();
      final aheadBehind = await _computeAheadBehind(remoteHeadCommitId);

      return VcOperationResultData(
        result: VcOperationResult.success,
        data: VcRepositoryStatus(
          branchName: branch?.name ?? 'main',
          headCommitId: repo.headCommitId,
          stagedCount: stagedCount,
          unstagedCount: unstagedCount,
          untrackedCount: untrackedCount,
          ahead: aheadBehind.$1,
          behind: aheadBehind.$2,
          isClean:
              stagedCount == 0 && unstagedCount == 0 && untrackedCount == 0,
          isInitialized: true,
        ),
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to get status: $e',
      );
    }
  }

  Future<List<VcFileChange>> _scanWorkingDirectory(VcRepository repo) async {
    final changes = <VcFileChange>[];
    final localPath = repo.localPath;
    final ignoreRules = await _loadIgnoreRules(localPath);

    if (!await Directory(localPath).exists()) {
      return changes;
    }

    final lastCommit = await _db.getCommit(repo.headCommitId);
    final lastTree = lastCommit != null
        ? await _db.getTreeEntries(lastCommit.id)
        : <VcTreeEntry>[];

    final lastTreeMap = {for (var e in lastTree) e.relativePath: e};

    // 收集所有需要处理的文件路径
    final filesToProcess = <String, File>{};
    await for (final entity in Directory(localPath).list(recursive: true)) {
      if (entity is! File) continue;
      final relativePath = p.relative(entity.path, from: localPath);
      if (_isIgnoredPath(relativePath, ignoreRules)) continue;
      filesToProcess[relativePath] = entity;
    }

    // 使用优化的批量哈希计算
    final filePaths = filesToProcess.values.map((f) => f.path).toList();
    final hashResults = await BinaryOptimizationUtil.batchCalculateHashes(
      filePaths,
      parallelism: 4,
    );

    for (final entry in filesToProcess.entries) {
      final relativePath = entry.key;
      final file = entry.value;
      final stat = await file.stat();
      final newHash = hashResults[file.path] ?? '';

      if (lastTreeMap.containsKey(relativePath)) {
        final oldEntry = lastTreeMap[relativePath]!;
        // 快速路径：先检查文件大小和修改时间
        if (stat.size != oldEntry.fileSize) {
          // 大小不同，确定已修改
          changes.add(
            VcFileChange(
              repositoryId: repositoryId,
              relativePath: relativePath,
              changeType: VcChangeType.modified,
              status: VcFileStatus.modified,
              oldSize: oldEntry.fileSize,
              newSize: stat.size,
              oldHash: oldEntry.fileHash,
              newHash: newHash,
            ),
          );
        } else if (oldEntry.fileHash != newHash) {
          // 大小相同但哈希不同
          changes.add(
            VcFileChange(
              repositoryId: repositoryId,
              relativePath: relativePath,
              changeType: VcChangeType.modified,
              status: VcFileStatus.modified,
              oldSize: oldEntry.fileSize,
              newSize: stat.size,
              oldHash: oldEntry.fileHash,
              newHash: newHash,
            ),
          );
        }
        lastTreeMap.remove(relativePath);
      } else {
        changes.add(
          VcFileChange(
            repositoryId: repositoryId,
            relativePath: relativePath,
            changeType: VcChangeType.added,
            status: VcFileStatus.untracked,
            newSize: stat.size,
            newHash: newHash,
          ),
        );
      }
    }

    for (final entry in lastTreeMap.values) {
      changes.add(
        VcFileChange(
          repositoryId: repositoryId,
          relativePath: entry.relativePath,
          changeType: VcChangeType.deleted,
          status: VcFileStatus.modified,
          oldSize: entry.fileSize,
          oldHash: entry.fileHash,
        ),
      );
    }

    return changes;
  }

  Future<String> _selectLatestRemoteHeadCommitId() async {
    final remotes = await _db.getRemotesByRepository(repositoryId);
    String selectedHead = '';
    String latestSyncTime = '';

    for (final remote in remotes) {
      final head = (remote['last_remote_head_commit_id'] as String?) ?? '';
      if (head.isEmpty) {
        continue;
      }

      final syncTime = (remote['last_sync_time'] as String?) ?? '';
      if (selectedHead.isEmpty || syncTime.compareTo(latestSyncTime) > 0) {
        selectedHead = head;
        latestSyncTime = syncTime;
      }
    }

    return selectedHead;
  }

  Future<(int ahead, int behind)> _computeAheadBehind(
    String remoteHeadCommitId,
  ) async {
    if (remoteHeadCommitId.isEmpty) {
      return (0, 0);
    }

    final repo = await _getRepository();
    if (repo == null || repo.headCommitId.isEmpty) {
      return (0, 0);
    }

    final localAncestors = await _collectAncestors(repo.headCommitId);
    final remoteAncestors = await _collectAncestors(remoteHeadCommitId);

    final ahead = localAncestors.keys
        .where((id) => !remoteAncestors.containsKey(id))
        .length;
    final behind = remoteAncestors.keys
        .where((id) => !localAncestors.containsKey(id))
        .length;

    return (ahead, behind);
  }

  Future<Map<String, int>> _collectAncestors(String startCommitId) async {
    final visited = <String, int>{};
    final queue = <(String id, int depth)>[(startCommitId, 0)];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current.$1.isEmpty || visited.containsKey(current.$1)) {
        continue;
      }

      visited[current.$1] = current.$2;
      final commit = await _db.getCommit(current.$1);
      if (commit == null) {
        continue;
      }

      if (commit.parentCommitId.isNotEmpty) {
        queue.add((commit.parentCommitId, current.$2 + 1));
      }
      if (commit.secondParentId.isNotEmpty) {
        queue.add((commit.secondParentId, current.$2 + 1));
      }
    }

    return visited;
  }

  Future<VcOperationResultData> add({
    List<String>? files,
    bool all = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final changes = await _scanWorkingDirectory(repo);

      List<VcFileChange> toAdd;
      if (all) {
        toAdd = changes;
      } else if (files != null && files.isNotEmpty) {
        toAdd = changes.where((c) => files.contains(c.relativePath)).toList();
      } else {
        toAdd = changes;
      }

      if (toAdd.isEmpty) {
        return VcOperationResultData(
          result: VcOperationResult.nothingToCommit,
          message: 'Nothing to add',
        );
      }

      for (final change in toAdd) {
        final entry = VcStagingEntry(
          repositoryId: repositoryId,
          relativePath: change.relativePath,
          oldPath: change.oldPath,
          changeType: change.changeType.name,
          oldSize: change.oldSize,
          newSize: change.newSize,
          oldHash: change.oldHash,
          newHash: change.newHash,
          isStaged: true,
        );
        await _db.insertStagingEntry(entry.toMap());
      }

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Added ${toAdd.length} file(s) to staging',
        data: toAdd.length,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to add files: $e',
      );
    }
  }

  Future<VcOperationResultData> reset({
    List<String>? files,
    bool all = false,
    bool hard = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      if (hard) {
        if (!all && files == null) {
          return VcOperationResultData(
            result: VcOperationResult.error,
            message: 'Hard reset requires --all or file list',
          );
        }

        final headCommit = await _db.getCommit(repo.headCommitId);
        if (headCommit == null) {
          return VcOperationResultData(
            result: VcOperationResult.success,
            message: 'Nothing to reset (no commits)',
          );
        }

        final tree = await _db.getTreeEntries(headCommit.id);
        final treeMap = {for (var e in tree) e.relativePath: e};

        List<String> toReset;
        if (all) {
          toReset = treeMap.keys.toList();
        } else {
          toReset = files ?? [];
        }

        for (final path in toReset) {
          if (!treeMap.containsKey(path)) continue;

          final entry = treeMap[path]!;
          final objectPath = p.join(
            repo.localPath,
            _versionsDir,
            entry.fileHash,
          );

          if (await File(objectPath).exists()) {
            final targetPath = p.join(repo.localPath, path);
            await File(targetPath).parent.create(recursive: true);
            // 使用优化的硬链接或复制
            final success = await BinaryOptimizationUtil.createHardLink(
              sourcePath: objectPath,
              targetPath: targetPath,
            );
            if (!success) {
              // 回退到普通复制
              await File(objectPath).copy(targetPath);
            }
          }
        }

        return VcOperationResultData(
          result: VcOperationResult.success,
          message: 'Hard reset ${toReset.length} file(s)',
        );
      } else {
        List<String> toUnstage;
        if (all) {
          final entries = await _db.getStagingEntries(repositoryId);
          toUnstage = entries
              .where((e) => e.isStaged)
              .map((e) => e.id)
              .toList();
        } else if (files != null && files.isNotEmpty) {
          final entries = await _db.getStagingEntries(repositoryId);
          toUnstage = entries
              .where((e) => e.isStaged && files.contains(e.relativePath))
              .map((e) => e.id)
              .toList();
        } else {
          final entries = await _db.getStagingEntries(repositoryId);
          toUnstage = entries
              .where((e) => e.isStaged)
              .map((e) => e.id)
              .toList();
        }

        for (final id in toUnstage) {
          await _db.deleteStagingEntry(id);
        }

        return VcOperationResultData(
          result: VcOperationResult.success,
          message: 'Unstaged ${toUnstage.length} file(s)',
        );
      }
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to reset: $e',
      );
    }
  }

  Future<VcOperationResultData> _performCommit({
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final stagingEntries = await _db.getStagingEntries(repositoryId);
      final staged = stagingEntries.where((e) => e.isStaged).toList();

      if (staged.isEmpty) {
        return VcOperationResultData(
          result: VcOperationResult.nothingToCommit,
          message: 'Nothing to commit (use "add" to stage changes)',
        );
      }

      final branch = await _db.getBranch(repo.currentBranchId);
      if (branch == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Current branch not found',
        );
      }

      final commit = VcCommit(
        repositoryId: repositoryId,
        branchId: branch.id,
        parentCommitId: repo.headCommitId,
        message: message,
        authorName: authorName,
        authorEmail: authorEmail,
        fileCount: staged.length,
      );

      await _db.insertCommit(commit.toMap());

      int additions = 0;
      int deletions = 0;

      for (final entry in staged) {
        final treeEntry = VcTreeEntry(
          commitId: commit.id,
          relativePath: entry.relativePath,
          fileSize: entry.newSize,
          fileHash: entry.newHash,
        );
        await _db.insertTreeEntry(treeEntry.toMap());

        final fileChange = VcFileChange(
          repositoryId: repositoryId,
          commitId: commit.id,
          relativePath: entry.relativePath,
          oldPath: entry.oldPath,
          changeType: VcChangeType.values.firstWhere(
            (e) => e.name == entry.changeType,
            orElse: () => VcChangeType.modified,
          ),
          status: VcFileStatus.committed,
          oldSize: entry.oldSize,
          newSize: entry.newSize,
          oldHash: entry.oldHash,
          newHash: entry.newHash,
        );
        await _db.insertFileChange(fileChange.toMap());

        if (entry.newSize > entry.oldSize) {
          additions += (entry.newSize - entry.oldSize).toInt();
        } else {
          deletions += (entry.oldSize - entry.newSize).toInt();
        }

        if (entry.newHash.isNotEmpty) {
          final sourcePath = p.join(repo.localPath, entry.relativePath);
          final objectPath = p.join(
            repo.localPath,
            _versionsDir,
            entry.newHash,
          );
          if (await File(sourcePath).exists() &&
              !await File(objectPath).exists()) {
            await File(objectPath).parent.create(recursive: true);
            // 使用优化的硬链接或复制
            final success = await BinaryOptimizationUtil.createHardLink(
              sourcePath: sourcePath,
              targetPath: objectPath,
            );
            if (!success) {
              // 回退到普通复制
              await File(sourcePath).copy(objectPath);
            }
          }
        }

        await _db.deleteStagingEntry(entry.id);
      }

      await _db.updateCommit(commit.id, {
        'additions': additions,
        'deletions': deletions,
      });

      await _db.updateBranch(branch.id, {'commit_id': commit.id});
      await _db.updateRepository(repositoryId, {
        'head_commit_id': commit.id,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: '[${commit.shortId}] ${commit.shortMessage}',
        data: commit,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to commit: $e',
      );
    }
  }

  Future<VcOperationResultData> commit({
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    return await _performCommit(
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
  }

  Future<VcOperationResultData> branch({
    required String name,
    String? commitId,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final existing = await _db.getBranchByName(repositoryId, name);
      if (existing != null) {
        return VcOperationResultData(
          result: VcOperationResult.branchExists,
          message: 'Branch "$name" already exists',
        );
      }

      final newBranch = VcBranch(
        repositoryId: repositoryId,
        name: name,
        commitId: commitId ?? repo.headCommitId,
      );

      await _db.insertBranch(newBranch.toMap());

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Created branch "$name"',
        data: newBranch,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to create branch: $e',
      );
    }
  }

  Future<VcOperationResultData> checkout({
    String? branchName,
    String? commitId,
    bool create = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final statusResult = await status();
      final repoStatus = statusResult.data as VcRepositoryStatus;
      if (!repoStatus.isClean) {
        return VcOperationResultData(
          result: VcOperationResult.uncommittedChanges,
          message: 'Uncommitted changes, please commit or stash first',
        );
      }

      if (branchName != null) {
        if (create) {
          final createResult = await branch(name: branchName);
          if (!createResult.isSuccess) {
            return createResult;
          }
        }

        final targetBranch = await _db.getBranchByName(
          repositoryId,
          branchName,
        );
        if (targetBranch == null) {
          return VcOperationResultData(
            result: VcOperationResult.branchNotFound,
            message: 'Branch "$branchName" not found',
          );
        }

        if (targetBranch.commitId.isNotEmpty) {
          await _restoreCommit(repo, targetBranch.commitId);
        }

        await _db.updateRepository(repositoryId, {
          'current_branch_id': targetBranch.id,
          'head_commit_id': targetBranch.commitId,
          'updated_at': DateTime.now().toIso8601String(),
        });

        return VcOperationResultData(
          result: VcOperationResult.success,
          message: 'Switched to branch "$branchName"',
          data: targetBranch,
        );
      }

      if (commitId != null) {
        final targetCommit = await _db.getCommit(commitId);
        if (targetCommit == null) {
          return VcOperationResultData(
            result: VcOperationResult.error,
            message: 'Commit not found',
          );
        }

        await _restoreCommit(repo, commitId);

        await _db.updateRepository(repositoryId, {
          'head_commit_id': commitId,
          'updated_at': DateTime.now().toIso8601String(),
        });

        return VcOperationResultData(
          result: VcOperationResult.success,
          message: 'HEAD is now at ${targetCommit.shortId}',
          data: targetCommit,
        );
      }

      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Must specify branch or commit',
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to checkout: $e',
      );
    }
  }

  Future<void> _restoreCommit(VcRepository repo, String commitId) async {
    final tree = await _db.getTreeEntries(commitId);
    final ignoreRules = await _loadIgnoreRules(repo.localPath);

    final existingFiles = <String>[];
    await for (final entity in Directory(
      repo.localPath,
    ).list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: repo.localPath);
        if (!_isIgnoredPath(relativePath, ignoreRules)) {
          existingFiles.add(relativePath);
        }
      }
    }

    final treePaths = tree.map((e) => e.relativePath).toSet();

    for (final path in existingFiles) {
      if (!treePaths.contains(path)) {
        final filePath = p.join(repo.localPath, path);
        if (await File(filePath).exists()) {
          await File(filePath).delete();
        }
      }
    }

    for (final entry in tree) {
      final objectPath = p.join(repo.localPath, _versionsDir, entry.fileHash);
      final targetPath = p.join(repo.localPath, entry.relativePath);

      if (await File(objectPath).exists()) {
        await File(targetPath).parent.create(recursive: true);
        // 使用优化的硬链接或复制
        final success = await BinaryOptimizationUtil.createHardLink(
          sourcePath: objectPath,
          targetPath: targetPath,
        );
        if (!success) {
          // 回退到普通复制
          await File(objectPath).copy(targetPath);
        }
      }
    }
  }

  Future<VcOperationResultData> revert({
    required String commitId,
    bool noCommit = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final commit = await _db.getCommit(commitId);
      if (commit == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Commit not found',
        );
      }

      final changes = await _db.getFileChangesByCommit(commitId);

      for (final change in changes) {
        final entry = VcStagingEntry(
          repositoryId: repositoryId,
          relativePath: change.relativePath,
          oldPath: change.oldPath,
          changeType: _invertChangeType(change.changeType).name,
          oldSize: change.newSize,
          newSize: change.oldSize,
          oldHash: change.newHash,
          newHash: change.oldHash,
          isStaged: true,
        );

        if (change.changeType == VcChangeType.added) {
          final filePath = p.join(repo.localPath, change.relativePath);
          if (await File(filePath).exists()) {
            await File(filePath).delete();
          }
        } else if (change.changeType == VcChangeType.deleted) {
          final objectPath = p.join(
            repo.localPath,
            _versionsDir,
            change.oldHash,
          );
          final targetPath = p.join(repo.localPath, change.relativePath);
          if (await File(objectPath).exists()) {
            await File(targetPath).parent.create(recursive: true);
            await File(objectPath).copy(targetPath);
          }
        } else {
          final objectPath = p.join(
            repo.localPath,
            _versionsDir,
            change.oldHash,
          );
          final targetPath = p.join(repo.localPath, change.relativePath);
          if (await File(objectPath).exists()) {
            await File(targetPath).parent.create(recursive: true);
            await File(objectPath).copy(targetPath);
          }
        }

        await _db.insertStagingEntry(entry.toMap());
      }

      if (!noCommit) {
        return await _performCommit(
          message:
              'Revert "${commit.shortMessage}"\n\nThis reverts commit ${commit.id}.',
        );
      }

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Reverted commit ${commit.shortId}',
        data: changes.length,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to revert: $e',
      );
    }
  }

  VcChangeType _invertChangeType(VcChangeType type) {
    switch (type) {
      case VcChangeType.added:
        return VcChangeType.deleted;
      case VcChangeType.deleted:
        return VcChangeType.added;
      default:
        return type;
    }
  }

  Future<VcOperationResultData> stash({
    String? message,
    bool includeUntracked = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final stagingEntries = await _db.getStagingEntries(repositoryId);
      final staged = stagingEntries.where((e) => e.isStaged).toList();

      if (staged.isEmpty) {
        return VcOperationResultData(
          result: VcOperationResult.nothingToCommit,
          message: 'No local changes to save',
        );
      }

      final stash = VcStash(
        repositoryId: repositoryId,
        branchId: repo.currentBranchId,
        message: message ?? 'WIP on ${await _getCurrentBranchName()}',
        fileCount: staged.length,
      );

      await _db.insertStash(stash.toMap());

      for (final entry in staged) {
        await _db.insertStashEntry({
          'stash_id': stash.id,
          'relative_path': entry.relativePath,
          'old_path': entry.oldPath,
          'change_type': entry.changeType,
          'old_size': entry.oldSize,
          'new_size': entry.newSize,
          'old_hash': entry.oldHash,
          'new_hash': entry.newHash,
        });

        if (entry.changeType == 'added') {
          final filePath = p.join(repo.localPath, entry.relativePath);
          if (await File(filePath).exists()) {
            await File(filePath).delete();
          }
        } else if (entry.oldHash.isNotEmpty) {
          final objectPath = p.join(
            repo.localPath,
            _versionsDir,
            entry.oldHash,
          );
          final targetPath = p.join(repo.localPath, entry.relativePath);
          if (await File(objectPath).exists()) {
            await File(targetPath).parent.create(recursive: true);
            await File(objectPath).copy(targetPath);
          }
        }

        await _db.deleteStagingEntry(entry.id);
      }

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Saved working directory to stash ${stash.shortId}',
        data: stash,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to stash: $e',
      );
    }
  }

  Future<VcOperationResultData> stashPop({String? stashId}) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final stashes = await _db.getStashes(repositoryId);
      if (stashes.isEmpty) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'No stash found',
        );
      }

      final stash = stashId != null
          ? stashes.firstWhere(
              (s) => s.id == stashId,
              orElse: () => stashes.first,
            )
          : stashes.first;

      final entries = await _db.getStashEntries(stash.id);

      for (final entry in entries) {
        final stagingEntry = VcStagingEntry(
          repositoryId: repositoryId,
          relativePath: entry['relative_path'] as String,
          oldPath: entry['old_path'] as String? ?? '',
          changeType: entry['change_type'] as String? ?? 'modified',
          oldSize: entry['old_size'] as int? ?? 0,
          newSize: entry['new_size'] as int? ?? 0,
          oldHash: entry['old_hash'] as String? ?? '',
          newHash: entry['new_hash'] as String? ?? '',
          isStaged: true,
        );
        await _db.insertStagingEntry(stagingEntry.toMap());
      }

      await _db.deleteStash(stash.id);

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Dropped stash ${stash.shortId}',
        data: entries.length,
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to pop stash: $e',
      );
    }
  }

  Future<List<VcCommit>> log({
    String? branchId,
    int? limit,
    String? since,
    String? until,
  }) async {
    try {
      await _ensureInitialized();
      return await _db.getCommits(
        repositoryId,
        branchId: branchId,
        limit: limit,
        since: since,
        until: until,
      );
    } catch (e) {
      return [];
    }
  }

  Future<List<VcBranch>> listBranches() async {
    try {
      await _ensureInitialized();
      return await _db.getBranches(repositoryId);
    } catch (e) {
      return [];
    }
  }

  Future<VcOperationResultData> deleteBranch(String branchName) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final branch = await _db.getBranchByName(repositoryId, branchName);
      if (branch == null) {
        return VcOperationResultData(
          result: VcOperationResult.branchNotFound,
          message: 'Branch "$branchName" not found',
        );
      }

      if (branch.isDefault) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Cannot delete default branch',
        );
      }

      if (repo.currentBranchId == branch.id) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Cannot delete current branch',
        );
      }

      await _db.deleteBranch(branch.id);

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Deleted branch "$branchName"',
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to delete branch: $e',
      );
    }
  }

  Future<List<VcFileDiff>> diff({
    String? commitId1,
    String? commitId2,
    bool cached = false,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) return [];

      final diffs = <VcFileDiff>[];

      if (cached) {
        final stagingEntries = await _db.getStagingEntries(repositoryId);
        final staged = stagingEntries.where((e) => e.isStaged).toList();

        for (final entry in staged) {
          final diff = await _computeDiff(
            repo,
            entry.oldHash,
            entry.newHash,
            entry.relativePath,
            entry.oldPath,
            entry.changeType,
          );
          diffs.add(diff);
        }
      } else if (commitId1 != null && commitId2 != null) {
        final tree1 = await _db.getTreeEntries(commitId1);
        final tree2 = await _db.getTreeEntries(commitId2);

        final map1 = {for (var e in tree1) e.relativePath: e};
        final map2 = {for (var e in tree2) e.relativePath: e};

        final allPaths = {...map1.keys, ...map2.keys};

        for (final path in allPaths) {
          final entry1 = map1[path];
          final entry2 = map2[path];

          if (entry1 == null) {
            diffs.add(
              VcFileDiff(relativePath: path, changeType: VcChangeType.added),
            );
          } else if (entry2 == null) {
            diffs.add(
              VcFileDiff(relativePath: path, changeType: VcChangeType.deleted),
            );
          } else if (entry1.fileHash != entry2.fileHash) {
            final diff = await _computeDiff(
              repo,
              entry1.fileHash,
              entry2.fileHash,
              path,
              '',
              'modified',
            );
            diffs.add(diff);
          }
        }
      } else {
        final changes = await _scanWorkingDirectory(repo);

        for (final change in changes) {
          final diff = await _computeDiff(
            repo,
            change.oldHash,
            change.newHash,
            change.relativePath,
            change.oldPath,
            change.changeType.name,
          );
          diffs.add(diff);
        }
      }

      return diffs;
    } catch (e) {
      return [];
    }
  }

  Future<VcFileDiff> _computeDiff(
    VcRepository repo,
    String oldHash,
    String newHash,
    String relativePath,
    String oldPath,
    String changeType,
  ) async {
    String? oldContent;
    String? newContent;

    if (oldHash.isNotEmpty) {
      final objectPath = p.join(repo.localPath, _versionsDir, oldHash);
      if (await File(objectPath).exists()) {
        try {
          oldContent = await File(objectPath).readAsString();
        } catch (_) {}
      }
    }

    if (newHash.isNotEmpty) {
      final filePath = p.join(repo.localPath, relativePath);
      if (await File(filePath).exists()) {
        try {
          newContent = await File(filePath).readAsString();
        } catch (_) {}
      }
    }

    final hunks = _computeLineDiff(oldContent ?? '', newContent ?? '');

    int additions = 0;
    int deletions = 0;

    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        if (line.type == 'add') additions++;
        if (line.type == 'delete') deletions++;
      }
    }

    return VcFileDiff(
      relativePath: relativePath,
      oldPath: oldPath,
      changeType: VcChangeType.values.firstWhere(
        (e) => e.name == changeType,
        orElse: () => VcChangeType.modified,
      ),
      hunks: hunks,
      additions: additions,
      deletions: deletions,
      isBinary: oldContent == null && newContent == null,
    );
  }

  List<VcDiffHunk> _computeLineDiff(String oldContent, String newContent) {
    final hunks = <VcDiffHunk>[];
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');

    if (oldContent.isEmpty && newContent.isEmpty) {
      return hunks;
    }

    if (oldContent.isEmpty) {
      final lines = <VcDiffLine>[];
      for (var i = 0; i < newLines.length; i++) {
        lines.add(
          VcDiffLine(
            oldLineNumber: -1,
            newLineNumber: i + 1,
            content: newLines[i],
            type: 'add',
          ),
        );
      }
      hunks.add(
        VcDiffHunk(
          oldStart: 0,
          oldCount: 0,
          newStart: 1,
          newCount: newLines.length,
          lines: lines,
        ),
      );
      return hunks;
    }

    if (newContent.isEmpty) {
      final lines = <VcDiffLine>[];
      for (var i = 0; i < oldLines.length; i++) {
        lines.add(
          VcDiffLine(
            oldLineNumber: i + 1,
            newLineNumber: -1,
            content: oldLines[i],
            type: 'delete',
          ),
        );
      }
      hunks.add(
        VcDiffHunk(
          oldStart: 1,
          oldCount: oldLines.length,
          newStart: 0,
          newCount: 0,
          lines: lines,
        ),
      );
      return hunks;
    }

    final diff = <VcDiffLine>[];
    int oldIdx = 0;
    int newIdx = 0;

    while (oldIdx < oldLines.length || newIdx < newLines.length) {
      if (oldIdx >= oldLines.length) {
        diff.add(
          VcDiffLine(
            oldLineNumber: -1,
            newLineNumber: newIdx + 1,
            content: newLines[newIdx],
            type: 'add',
          ),
        );
        newIdx++;
      } else if (newIdx >= newLines.length) {
        diff.add(
          VcDiffLine(
            oldLineNumber: oldIdx + 1,
            newLineNumber: -1,
            content: oldLines[oldIdx],
            type: 'delete',
          ),
        );
        oldIdx++;
      } else if (oldLines[oldIdx] == newLines[newIdx]) {
        diff.add(
          VcDiffLine(
            oldLineNumber: oldIdx + 1,
            newLineNumber: newIdx + 1,
            content: oldLines[oldIdx],
            type: 'context',
          ),
        );
        oldIdx++;
        newIdx++;
      } else {
        bool found = false;

        for (var i = newIdx; i < newLines.length && i < newIdx + 3; i++) {
          if (oldLines[oldIdx] == newLines[i]) {
            for (var j = newIdx; j < i; j++) {
              diff.add(
                VcDiffLine(
                  oldLineNumber: -1,
                  newLineNumber: j + 1,
                  content: newLines[j],
                  type: 'add',
                ),
              );
            }
            diff.add(
              VcDiffLine(
                oldLineNumber: oldIdx + 1,
                newLineNumber: i + 1,
                content: oldLines[oldIdx],
                type: 'context',
              ),
            );
            oldIdx++;
            newIdx = i + 1;
            found = true;
            break;
          }
        }

        if (!found) {
          diff.add(
            VcDiffLine(
              oldLineNumber: oldIdx + 1,
              newLineNumber: -1,
              content: oldLines[oldIdx],
              type: 'delete',
            ),
          );
          oldIdx++;
        }
      }
    }

    hunks.add(
      VcDiffHunk(
        oldStart: 1,
        oldCount: oldLines.length,
        newStart: 1,
        newCount: newLines.length,
        lines: diff,
      ),
    );

    return hunks;
  }

  Future<String> _getCurrentBranchName() async {
    final repo = await _getRepository();
    if (repo == null) return 'HEAD';

    final branch = await _db.getBranch(repo.currentBranchId);
    return branch?.name ?? 'HEAD';
  }

  Future<List<VcConflictFile>> detectConflicts() async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) return [];

      final entries = await _db.getStagingEntries(repositoryId);
      final stagedPaths = entries
          .where((e) => e.isStaged)
          .map((e) => e.relativePath)
          .toSet();
      final ignoreRules = await _loadIgnoreRules(repo.localPath);

      final conflicts = <VcConflictFile>[];

      await for (final entity in Directory(
        repo.localPath,
      ).list(recursive: true)) {
        if (entity is! File) continue;

        final relativePath = p.relative(entity.path, from: repo.localPath);
        if (_isIgnoredPath(relativePath, ignoreRules)) continue;

        String content;
        try {
          content = await entity.readAsString();
        } catch (_) {
          continue;
        }

        final markerBlocks = _countConflictBlocks(content);
        if (markerBlocks <= 0) continue;

        conflicts.add(
          VcConflictFile(
            relativePath: relativePath,
            markerBlocks: markerBlocks,
            isStaged: stagedPaths.contains(relativePath),
          ),
        );
      }

      conflicts.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      return conflicts;
    } catch (_) {
      return [];
    }
  }

  Future<VcOperationResultData> resolveConflict({
    required String relativePath,
    VcConflictResolutionStrategy strategy = VcConflictResolutionStrategy.manual,
    String? resolvedContent,
    bool stage = true,
  }) async {
    try {
      await _ensureInitialized();
      final repo = await _getRepository();
      if (repo == null) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'Repository not found',
        );
      }

      final filePath = p.join(repo.localPath, relativePath);
      final file = File(filePath);
      if (!await file.exists()) {
        return VcOperationResultData(
          result: VcOperationResult.error,
          message: 'File not found: $relativePath',
        );
      }

      var content = await file.readAsString();

      if (strategy == VcConflictResolutionStrategy.manual) {
        if (resolvedContent != null) {
          content = resolvedContent;
        }
      } else {
        final merged = _applyConflictResolution(content, strategy);
        if (merged == null) {
          return VcOperationResultData(
            result: VcOperationResult.conflict,
            message:
                'Conflict blocks are malformed and cannot be auto-resolved',
          );
        }
        content = merged;
      }

      if (_countConflictBlocks(content) > 0) {
        return VcOperationResultData(
          result: VcOperationResult.conflict,
          message: 'Conflict markers still exist, please resolve manually',
        );
      }

      await file.writeAsString(content);

      if (stage) {
        final oldEntry = await _getHeadTreeEntry(relativePath);
        final stat = await file.stat();
        final newHash = await ChecksumUtil.calculateCrc32Chunked(file.path);

        final stagingEntry = VcStagingEntry(
          repositoryId: repositoryId,
          relativePath: relativePath,
          changeType: oldEntry == null ? 'added' : 'modified',
          oldSize: oldEntry?.fileSize ?? 0,
          newSize: stat.size,
          oldHash: oldEntry?.fileHash ?? '',
          newHash: newHash,
          isStaged: true,
        );

        await _db.insertStagingEntry(stagingEntry.toMap());
      }

      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Resolved conflict for $relativePath',
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to resolve conflict: $e',
      );
    }
  }

  Future<VcTreeEntry?> _getHeadTreeEntry(String relativePath) async {
    final repo = await _getRepository();
    if (repo == null || repo.headCommitId.isEmpty) return null;

    final tree = await _db.getTreeEntries(repo.headCommitId);
    for (final entry in tree) {
      if (entry.relativePath == relativePath) {
        return entry;
      }
    }
    return null;
  }

  int _countConflictBlocks(String content) {
    final begin = RegExp(
      r'^<<<<<<< ',
      multiLine: true,
    ).allMatches(content).length;
    final middle = RegExp(
      r'^=======$',
      multiLine: true,
    ).allMatches(content).length;
    final end = RegExp(
      r'^>>>>>>> ',
      multiLine: true,
    ).allMatches(content).length;

    if (begin == 0) return 0;
    if (begin != middle || begin != end) return -1;
    return begin;
  }

  String? _applyConflictResolution(
    String content,
    VcConflictResolutionStrategy strategy,
  ) {
    final lines = content.split('\n');
    final output = <String>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (!line.startsWith('<<<<<<< ')) {
        output.add(line);
        i++;
        continue;
      }

      i++;
      final ours = <String>[];
      while (i < lines.length && !lines[i].startsWith('=======')) {
        ours.add(lines[i]);
        i++;
      }
      if (i >= lines.length) return null;

      i++;
      final theirs = <String>[];
      while (i < lines.length && !lines[i].startsWith('>>>>>>> ')) {
        theirs.add(lines[i]);
        i++;
      }
      if (i >= lines.length) return null;

      i++;
      output.addAll(
        strategy == VcConflictResolutionStrategy.ours ? ours : theirs,
      );
    }

    return output.join('\n');
  }

  Future<void> _writeIgnoreRules(
    String repoPath,
    List<String> ignoreRules,
  ) async {
    final merged = <String>{..._defaultIgnoreRules};
    for (final rule in ignoreRules) {
      final normalized = rule.trim();
      if (normalized.isEmpty || normalized.startsWith('#')) continue;
      merged.add(normalized);
    }

    final filePath = p.join(repoPath, _ignoreFileName);
    final file = File(filePath);
    if (await file.exists()) {
      final existing = await _loadIgnoreRules(repoPath);
      merged.addAll(existing);
    }

    final content = [
      '# NanoSync ignore rules',
      '# One pattern per line',
      ...merged,
      '',
    ].join('\n');
    await file.writeAsString(content);
  }

  Future<List<String>> _loadIgnoreRules(String repoPath) async {
    final rules = <String>[..._defaultIgnoreRules];
    final filePath = p.join(repoPath, _ignoreFileName);
    final file = File(filePath);

    if (!await file.exists()) {
      return rules;
    }

    final lines = await file.readAsLines();
    for (final line in lines) {
      final rule = line.trim();
      if (rule.isEmpty || rule.startsWith('#')) continue;
      rules.add(rule);
    }

    return rules.toSet().toList();
  }

  bool _isIgnoredPath(String relativePath, List<String> ignoreRules) {
    final path = relativePath.replaceAll('\\', '/');

    for (final rawRule in ignoreRules) {
      final rule = rawRule.trim().replaceAll('\\', '/');
      if (rule.isEmpty) continue;

      if (rule.endsWith('/')) {
        final prefix = rule.substring(0, rule.length - 1);
        if (path == prefix || path.startsWith('$prefix/')) {
          return true;
        }
      }

      if (rule.contains('*') || rule.contains('?')) {
        final regex = _globToRegex(rule);
        if (regex.hasMatch(path)) {
          return true;
        }
      }

      if (path == rule || path.startsWith('$rule/')) {
        return true;
      }
    }

    return false;
  }

  RegExp _globToRegex(String pattern) {
    final escaped = RegExp.escape(
      pattern,
    ).replaceAll(r'\*', '.*').replaceAll(r'\?', '.');
    return RegExp('^$escaped\$');
  }

  Future<List<VcFileChange>> getUnstagedChanges() async {
    try {
      final repo = await _getRepository();
      if (repo == null) return [];

      return await _scanWorkingDirectory(repo);
    } catch (e) {
      return [];
    }
  }

  Future<List<VcStagingEntry>> getStagedChanges() async {
    try {
      final entries = await _db.getStagingEntries(repositoryId);
      return entries.where((e) => e.isStaged).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<VcStash>> listStashes() async {
    try {
      return await _db.getStashes(repositoryId);
    } catch (e) {
      return [];
    }
  }

  Future<VcOperationResultData> deleteStash(String stashId) async {
    try {
      await _db.deleteStash(stashId);
      return VcOperationResultData(
        result: VcOperationResult.success,
        message: 'Deleted stash',
      );
    } catch (e) {
      return VcOperationResultData(
        result: VcOperationResult.error,
        message: 'Failed to delete stash: $e',
      );
    }
  }
}
