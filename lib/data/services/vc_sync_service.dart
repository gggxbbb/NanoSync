import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/sync_log.dart';
import '../models/vc_repository.dart';
import 'app_log_service.dart';
import 'vc_engine.dart';
import '../vc_database.dart';

class VcStateImportResult {
  final bool imported;
  final String repositoryId;
  final String remoteHeadCommitId;

  VcStateImportResult({
    required this.imported,
    this.repositoryId = '',
    this.remoteHeadCommitId = '',
  });
}

class VcSyncService {
  static const int _schemaVersion = 2;
  static const String _stateFileName = 'repository_state.json';

  final VcDatabase _db;
  final AppLogService _appLog;

  VcSyncService({VcDatabase? db, AppLogService? appLog})
    : _db = db ?? VcDatabase.instance,
      _appLog = appLog ?? AppLogService.instance;

  String getStateFilePath(String localPath) {
    return p.join(localPath, '.nanosync', _stateFileName);
  }

  Future<VcRepository> ensureRepositoryForLocalPath({
    required String localPath,
    required String preferredName,
  }) async {
    final existing = await _db.getRepositoryByLocalPath(localPath);
    if (existing != null) {
      if (!existing.isInitialized) {
        final engine = VcEngine(repositoryId: existing.id, db: _db);
        await engine.init(name: 'main');
        final refreshed = await _db.getRepository(existing.id);
        if (refreshed != null) {
          return refreshed;
        }
      }
      return existing;
    }

    final repo = VcRepository(name: preferredName, localPath: localPath);
    await _db.insertRepository(repo.toMap());
    final engine = VcEngine(repositoryId: repo.id, db: _db);
    await engine.init(name: 'main');

    final created = await _db.getRepository(repo.id);
    return created ?? repo;
  }

  Future<bool> exportRepositoryState(String localPath) async {
    await _appLog.debug(
      category: 'vc_sync',
      message: 'Export repository state started',
      source: 'VcSyncService.exportRepositoryState',
      context: {'localPath': localPath},
    );

    final repo = await _db.getRepositoryByLocalPath(localPath);
    if (repo == null || !repo.isInitialized) {
      await _appLog.warning(
        category: 'vc_sync',
        message: 'Export repository state skipped',
        source: 'VcSyncService.exportRepositoryState',
        details: 'Repository not found or not initialized',
        context: {'localPath': localPath},
      );
      return false;
    }

    final branches = await _db.getBranches(repo.id);
    final commits = await _db.getCommits(repo.id);

    final treesByCommit = <String, List<Map<String, dynamic>>>{};
    final changesByCommit = <String, List<Map<String, dynamic>>>{};

    for (final commit in commits) {
      final treeEntries = await _db.getTreeEntries(commit.id);
      final fileChanges = await _db.getFileChangesByCommit(commit.id);
      treesByCommit[commit.id] = treeEntries.map((e) => e.toMap()).toList();
      changesByCommit[commit.id] = fileChanges.map((e) => e.toMap()).toList();
    }

    final remotes = await _db.getRemotesByRepository(repo.id);
    final syncRecords = await _db.getSyncRecordsByRepository(
      repo.id,
      limit: 300,
    );

    final state = <String, dynamic>{
      'schema_version': _schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'repository': repo.toMap(),
      'branches': branches.map((e) => e.toMap()).toList(),
      'commits': commits.map((e) => e.toMap()).toList(),
      'trees_by_commit': treesByCommit,
      'changes_by_commit': changesByCommit,
      'remotes': remotes,
      'sync_records': syncRecords,
    };

    final stateFile = File(getStateFilePath(localPath));
    await stateFile.parent.create(recursive: true);
    await stateFile.writeAsString(jsonEncode(state));
    await _appLog.info(
      category: 'vc_sync',
      message: 'Export repository state completed',
      source: 'VcSyncService.exportRepositoryState',
      repositoryId: repo.id,
      context: {'commits': commits.length, 'branches': branches.length},
    );
    return true;
  }

  Future<VcStateImportResult> importRepositoryState(String localPath) async {
    await _appLog.debug(
      category: 'vc_sync',
      message: 'Import repository state started',
      source: 'VcSyncService.importRepositoryState',
      context: {'localPath': localPath},
    );

    final stateFile = File(getStateFilePath(localPath));
    if (!await stateFile.exists()) {
      return VcStateImportResult(imported: false);
    }

    final raw = await stateFile.readAsString();
    if (raw.trim().isEmpty) {
      return VcStateImportResult(imported: false);
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return VcStateImportResult(imported: false);
    }

    final rawRepo = _asMap(decoded['repository']);
    if (rawRepo == null) {
      return VcStateImportResult(imported: false);
    }

    final existingRepoByPath = await _db.getRepositoryByLocalPath(localPath);
    final sourceRepoId = _asString(rawRepo['id']);
    final repositoryId = existingRepoByPath?.id.isNotEmpty == true
        ? existingRepoByPath!.id
        : (sourceRepoId.isNotEmpty ? sourceRepoId : _generateId());

    final repositoryMap = Map<String, dynamic>.from(rawRepo);
    repositoryMap['id'] = repositoryId;
    repositoryMap['local_path'] = localPath;
    repositoryMap['is_initialized'] = 1;
    repositoryMap['created_at'] = _ensureIsoTime(repositoryMap['created_at']);
    repositoryMap['updated_at'] = DateTime.now().toIso8601String();

    await _db.insertRepository(repositoryMap);

    final rawBranches = _asListOfMap(decoded['branches']);
    final branchIdMap = <String, String>{};
    for (final item in rawBranches) {
      final branch = Map<String, dynamic>.from(item);
      final sourceBranchId = _asString(branch['id']);
      final branchId = sourceBranchId.isNotEmpty
          ? sourceBranchId
          : _generateId();
      if (sourceBranchId.isNotEmpty) {
        branchIdMap[sourceBranchId] = branchId;
      }
      branch['id'] = branchId;
      branch['repository_id'] = repositoryId;
      branch['created_at'] = _ensureIsoTime(branch['created_at']);
      await _db.insertBranch(branch);
    }

    final treesByCommitRaw =
        _asMap(decoded['trees_by_commit']) ?? const <String, dynamic>{};
    final changesByCommitRaw =
        _asMap(decoded['changes_by_commit']) ?? const <String, dynamic>{};

    final remoteIdMap = <String, String>{};
    final rawRemotes = _asListOfMap(decoded['remotes']);
    for (final item in rawRemotes) {
      final remote = Map<String, dynamic>.from(item);
      final sourceRemoteId = _asString(remote['id']);
      final remoteKey = _asString(remote['remote_key']);
      if (remoteKey.isEmpty) {
        continue;
      }

      final existingRemote = await _db.getRemoteByKey(repositoryId, remoteKey);
      final targetRemoteId = existingRemote != null
          ? _asString(existingRemote['id'])
          : (sourceRemoteId.isNotEmpty ? sourceRemoteId : _generateId());

      if (sourceRemoteId.isNotEmpty) {
        remoteIdMap[sourceRemoteId] = targetRemoteId;
      }

      remote['id'] = targetRemoteId;
      remote['repository_id'] = repositoryId;
      remote['created_at'] = _ensureIsoTime(remote['created_at']);
      remote['updated_at'] = DateTime.now().toIso8601String();
      await _db.insertRemote(remote);
    }

    final rawCommits = _asListOfMap(decoded['commits']);
    for (final item in rawCommits) {
      final commit = Map<String, dynamic>.from(item);
      final sourceBranchId = _asString(commit['branch_id']);
      if (branchIdMap.containsKey(sourceBranchId)) {
        commit['branch_id'] = branchIdMap[sourceBranchId];
      }
      commit['repository_id'] = repositoryId;
      commit['authored_at'] = _ensureIsoTime(commit['authored_at']);
      commit['committed_at'] = _ensureIsoTime(commit['committed_at']);
      await _db.insertCommit(commit);

      final commitId = _asString(commit['id']);
      if (commitId.isEmpty) {
        continue;
      }

      final rawTrees = _asListOfMap(treesByCommitRaw[commitId]);
      for (final treeItem in rawTrees) {
        final tree = Map<String, dynamic>.from(treeItem);
        tree['commit_id'] = commitId;
        tree['created_at'] = _ensureIsoTime(tree['created_at']);
        await _db.insertTreeEntry(tree);
      }

      final rawChanges = _asListOfMap(changesByCommitRaw[commitId]);
      for (final changeItem in rawChanges) {
        final change = Map<String, dynamic>.from(changeItem);
        change['repository_id'] = repositoryId;
        change['commit_id'] = commitId;
        change['created_at'] = _ensureIsoTime(change['created_at']);
        await _db.insertFileChange(change);
      }
    }

    final rawSyncRecords = _asListOfMap(decoded['sync_records']);
    for (final item in rawSyncRecords) {
      final sourceRemoteId = _asString(item['remote_id']);
      String? targetRemoteId;
      if (sourceRemoteId.isNotEmpty &&
          remoteIdMap.containsKey(sourceRemoteId)) {
        targetRemoteId = remoteIdMap[sourceRemoteId];
      }

      final normalized = <String, dynamic>{
        'id': _asString(item['id']).isEmpty
            ? _generateId()
            : _asString(item['id']),
        'repository_id': repositoryId,
        'remote_id': targetRemoteId,
        'repository_name': _asString(item['repository_name']).isNotEmpty
            ? _asString(item['repository_name'])
            : _asString(item['task_name']),
        'sync_operation': _asString(item['sync_operation']).isNotEmpty
            ? _asString(item['sync_operation'])
            : _asString(item['sync_direction']),
        'status': _asString(item['status']),
        'started_at': _ensureIsoTime(item['started_at']),
        'ended_at': item['ended_at'] == null
            ? null
            : _ensureIsoTime(item['ended_at']),
        'total_files': _asInt(item['total_files']),
        'success_count': _asInt(item['success_count']),
        'fail_count': _asInt(item['fail_count']),
        'skip_count': _asInt(item['skip_count']),
        'conflict_count': _asInt(item['conflict_count']),
        'error_message': _asString(item['error_message']).isEmpty
            ? null
            : _asString(item['error_message']),
        'pre_commit_id': _asString(item['pre_commit_id']),
        'post_commit_id': _asString(item['post_commit_id']),
        'remote_head_commit_id': _asString(item['remote_head_commit_id']),
        'local_head_commit_id': _asString(item['local_head_commit_id']),
        'ahead_count': _asInt(item['ahead_count']),
        'behind_count': _asInt(item['behind_count']),
        'source_device_fingerprint': _asString(
          item['source_device_fingerprint'],
        ),
        'source_device_name': _asString(item['source_device_name']),
        'source_username': _asString(item['source_username']),
        'created_at': _ensureIsoTime(item['created_at']),
      };

      await _db.insertSyncRecord(normalized);
    }

    final mappedCurrentBranchId =
        branchIdMap[_asString(rawRepo['current_branch_id'])] ??
        _asString(rawRepo['current_branch_id']);

    await _db.updateRepository(repositoryId, {
      'current_branch_id': mappedCurrentBranchId,
      'head_commit_id': _asString(rawRepo['head_commit_id']),
      'is_initialized': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return VcStateImportResult(
      imported: true,
      repositoryId: repositoryId,
      remoteHeadCommitId: _asString(rawRepo['head_commit_id']),
    );
  }

  Future<void> updateRemoteHeads({
    required String remoteId,
    required String localHeadCommitId,
    String remoteHeadCommitId = '',
  }) async {
    await _db.updateRemote(remoteId, {
      'last_local_head_commit_id': localHeadCommitId,
      'last_remote_head_commit_id': remoteHeadCommitId,
      'last_sync_time': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<SyncLog>> getAllSyncLogs({int limit = 200}) async {
    final records = await _db.getAllSyncRecords(limit: limit);
    return records.map(_syncLogFromRecord).toList();
  }

  Future<void> clearAllSyncLogs() async {
    await _db.clearAllSyncRecords();
  }

  Future<void> recordRepositorySync({
    required String repositoryId,
    required String repositoryName,
    String? remoteId,
    required String syncOperation,
    required String status,
    required DateTime startedAt,
    DateTime? endedAt,
    int totalFiles = 0,
    int successCount = 0,
    int failCount = 0,
    int skipCount = 0,
    int conflictCount = 0,
    String? errorMessage,
    String preCommitId = '',
    String postCommitId = '',
    String remoteHeadCommitId = '',
    String localHeadCommitId = '',
    int aheadCount = 0,
    int behindCount = 0,
    String sourceDeviceFingerprint = '',
    String sourceDeviceName = '',
    String sourceUsername = '',
  }) async {
    await _appLog.debug(
      category: 'vc_sync',
      message: 'Record repository sync',
      source: 'VcSyncService.recordRepositorySync',
      repositoryId: repositoryId,
      context: {
        'operation': syncOperation,
        'status': status,
        'totalFiles': totalFiles,
        'successCount': successCount,
        'failCount': failCount,
      },
    );

    final nowIso = DateTime.now().toIso8601String();
    await _db.insertSyncRecord({
      'id': _generateId(),
      'repository_id': repositoryId,
      'remote_id': remoteId,
      'repository_name': repositoryName,
      'sync_operation': syncOperation,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'total_files': totalFiles,
      'success_count': successCount,
      'fail_count': failCount,
      'skip_count': skipCount,
      'conflict_count': conflictCount,
      'error_message': errorMessage,
      'pre_commit_id': preCommitId,
      'post_commit_id': postCommitId,
      'remote_head_commit_id': remoteHeadCommitId,
      'local_head_commit_id': localHeadCommitId,
      'ahead_count': aheadCount,
      'behind_count': behindCount,
      'source_device_fingerprint': sourceDeviceFingerprint,
      'source_device_name': sourceDeviceName,
      'source_username': sourceUsername,
      'created_at': nowIso,
    });
  }

  Future<(int ahead, int behind)> computeAheadBehind({
    required String repositoryId,
    required String remoteHeadCommitId,
  }) async {
    if (remoteHeadCommitId.isEmpty) {
      return (0, 0);
    }

    final repo = await _db.getRepository(repositoryId);
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

  SyncLog _syncLogFromRecord(Map<String, dynamic> record) {
    return SyncLog(
      id: _asString(record['id']),
      repositoryId: _asString(record['repository_id']),
      repositoryName: _asString(record['repository_name']),
      startTime: DateTime.parse(_asString(record['started_at'])),
      endTime: _asString(record['ended_at']).isEmpty
          ? null
          : DateTime.parse(_asString(record['ended_at'])),
      totalFiles: _asInt(record['total_files']),
      successCount: _asInt(record['success_count']),
      failCount: _asInt(record['fail_count']),
      skipCount: _asInt(record['skip_count']),
      conflictCount: _asInt(record['conflict_count']),
      status: _asString(record['status']),
      errorMessage: _asString(record['error_message']).isEmpty
          ? null
          : _asString(record['error_message']),
      sourceDeviceFingerprint: _asString(record['source_device_fingerprint']),
      sourceDeviceName: _asString(record['source_device_name']),
      sourceUsername: _asString(record['source_username']),
    );
  }

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  static String _asString(dynamic value) => value?.toString() ?? '';

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    return null;
  }

  static List<Map<String, dynamic>> _asListOfMap(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => _asMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static String _ensureIsoTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return DateTime.now().toIso8601String();
    }
    return text;
  }
}
