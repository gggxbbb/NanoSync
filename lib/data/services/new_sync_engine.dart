import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/utils/device_identity.dart';
import '../database/database_helper.dart';
import '../models/remote_connection.dart';
import '../models/sync_result.dart';
import '../vc_database.dart';
import 'remote_connection_manager.dart';
import 'repository_manager.dart';
import 'smb_service.dart';
import 'unc_service.dart';
import 'vc_engine.dart';
import 'vc_sync_service.dart';
import 'webdav_service.dart';

class NewSyncEngine {
  static NewSyncEngine? _instance;
  static NewSyncEngine get instance {
    _instance ??= NewSyncEngine._();
    return _instance!;
  }

  final DatabaseHelper _db;
  final VcDatabase _vcDb;
  final RepositoryManager _repoManager;
  final RemoteConnectionManager _connManager;
  final SmbService _smb;
  final UncService _unc;
  final WebDAVService _webdav;
  final VcSyncService _vcSync;
  final void Function(double progress, String message)? onProgress;
  final void Function(String error)? onError;

  NewSyncEngine._({
    DatabaseHelper? db,
    VcDatabase? vcDb,
    RepositoryManager? repoManager,
    RemoteConnectionManager? connManager,
    SmbService? smb,
    UncService? unc,
    WebDAVService? webdav,
    VcSyncService? vcSync,
    this.onProgress,
    this.onError,
  }) : _db = db ?? DatabaseHelper.instance,
       _vcDb = vcDb ?? VcDatabase.instance,
       _repoManager = repoManager ?? RepositoryManager.instance,
       _connManager = connManager ?? RemoteConnectionManager.instance,
       _smb = smb ?? SmbService(),
       _unc = unc ?? UncService(),
       _webdav = webdav ?? WebDAVService(),
       _vcSync = vcSync ?? VcSyncService();

  Future<FetchResult> fetch(Repository repo, {String? remoteName}) async {
    final startedAt = DateTime.now();
    String? resolvedRemoteId;
    String fetchError = '';
    String remoteHeadCommitId = '';
    int aheadCount = 0;
    int behindCount = 0;
    try {
      final remote = await _getEffectiveRemote(repo, remoteName);
      if (remote == null) {
        fetchError = 'No remote configured';
        return const FetchResult(error: 'No remote configured');
      }

      final resolvedRemoteName = remote['remote_name'] as String? ?? '';
      resolvedRemoteId = await _resolveVcRemoteId(repo.id, resolvedRemoteName);

      final conn = await _getConnection(remote['remote_name'] as String);
      if (conn == null) {
        fetchError = 'Remote connection not found';
        return const FetchResult(error: 'Remote connection not found');
      }

      onProgress?.call(0.1, 'Connecting to remote...');

      await _connect(conn);

      onProgress?.call(0.3, 'Downloading repository state...');

      final stateFilePath = p.join(
        repo.localPath,
        '.nanosync',
        'repository_state.json',
      );
      await _downloadFile(
        conn,
        '${remote['remote_path']}/.nanosync/repository_state.json',
        stateFilePath,
      );

      onProgress?.call(0.6, 'Importing repository state...');

      final importResult = await _vcSync.importRepositoryState(repo.localPath);
      remoteHeadCommitId = importResult.remoteHeadCommitId;

      if (importResult.imported && remoteHeadCommitId.isNotEmpty) {
        final aheadBehind = await _vcSync.computeAheadBehind(
          repositoryId: repo.id,
          remoteHeadCommitId: remoteHeadCommitId,
        );
        aheadCount = aheadBehind.$1;
        behindCount = aheadBehind.$2;

        onProgress?.call(0.9, 'Updating remote tracking...');

        final repoRemotes = await _db.getRepositoryRemotes(repo.id);
        for (final rr in repoRemotes) {
          if (rr['remote_name'] == remote['remote_name']) {
            await _db.updateRepositoryRemote(rr['id'] as String, {
              'last_fetch': DateTime.now().toIso8601String(),
            });
            break;
          }
        }

        onProgress?.call(1.0, 'Fetch complete');

        return FetchResult(
          ahead: aheadCount,
          behind: behindCount,
          remoteHead: remoteHeadCommitId,
          hasUpdates: true,
        );
      }

      return const FetchResult();
    } catch (e) {
      onError?.call(e.toString());
      fetchError = e.toString();
      return FetchResult(error: e.toString());
    } finally {
      final localHead = await _currentLocalHead(repo.id);
      await _recordSyncLog(
        repository: repo,
        remoteId: resolvedRemoteId,
        operation: 'fetch',
        status: fetchError.isEmpty ? 'success' : 'failed',
        startedAt: startedAt,
        endedAt: DateTime.now(),
        totalFiles: aheadCount + behindCount,
        successCount: fetchError.isEmpty ? (aheadCount + behindCount) : 0,
        failCount: fetchError.isEmpty ? 0 : 1,
        errorMessage: fetchError.isEmpty ? null : fetchError,
        remoteHeadCommitId: remoteHeadCommitId,
        localHeadCommitId: localHead,
        aheadCount: aheadCount,
        behindCount: behindCount,
      );
      _disconnect();
    }
  }

  Future<PushResult> push(
    Repository repo, {
    String? remoteName,
    bool force = false,
  }) async {
    final startedAt = DateTime.now();
    String? resolvedRemoteId;
    String remoteHeadCommitId = '';
    int pushedObjects = 0;
    String? pushError;
    try {
      final remote = await _getEffectiveRemote(repo, remoteName);
      if (remote == null) {
        pushError = 'No remote configured';
        return const PushResult(error: 'No remote configured');
      }

      final resolvedRemoteName = remote['remote_name'] as String? ?? '';
      resolvedRemoteId = await _resolveVcRemoteId(repo.id, resolvedRemoteName);

      final conn = await _getConnection(remote['remote_name'] as String);
      if (conn == null) {
        pushError = 'Remote connection not found';
        return const PushResult(error: 'Remote connection not found');
      }

      onProgress?.call(0.1, 'Fetching remote state...');

      final fetchResult = await fetch(
        repo,
        remoteName: remote['remote_name'] as String,
      );
      remoteHeadCommitId = fetchResult.remoteHead;

      if (fetchResult.behind > 0 && !force) {
        pushError = 'Remote has new commits. Pull first or use force.';
        return const PushResult(
          error: 'Remote has new commits. Pull first or use force.',
        );
      }

      onProgress?.call(0.3, 'Collecting objects to push...');

      final objects = await _collectObjectsToPush(repo, fetchResult.remoteHead);

      onProgress?.call(0.5, 'Uploading objects...');

      for (final objectHash in objects) {
        final objectPath = p.join(
          repo.localPath,
          '.nanosync',
          'objects',
          objectHash,
        );
        final remoteObjectPath =
            '${remote['remote_path']}/.nanosync/objects/$objectHash';

        if (await File(objectPath).exists()) {
          await _uploadFile(conn, objectPath, remoteObjectPath);
          pushedObjects++;
          onProgress?.call(
            0.5 + 0.3 * (pushedObjects / objects.length),
            'Uploading objects $pushedObjects/${objects.length}',
          );
        }
      }

      onProgress?.call(0.85, 'Updating remote state...');

      await _vcSync.exportRepositoryState(repo.localPath);
      await _uploadFile(
        conn,
        p.join(repo.localPath, '.nanosync', 'repository_state.json'),
        '${remote['remote_path']}/.nanosync/repository_state.json',
      );

      final config = repo.config;
      if (config != null) {
        await config.saveToFile(repo.localPath);
        await _uploadFile(
          conn,
          p.join(repo.localPath, '.nanosync', 'config.json'),
          '${remote['remote_path']}/.nanosync/config.json',
        );
      }

      onProgress?.call(0.95, 'Updating tracking...');

      final repoRemotes = await _db.getRepositoryRemotes(repo.id);
      for (final rr in repoRemotes) {
        if (rr['remote_name'] == remote['remote_name']) {
          await _db.updateRepositoryRemote(rr['id'] as String, {
            'last_sync': DateTime.now().toIso8601String(),
          });
          break;
        }
      }

      onProgress?.call(1.0, 'Push complete');

      return PushResult(
        pushedCommits: fetchResult.ahead,
        pushedObjects: pushedObjects,
        success: true,
      );
    } catch (e) {
      onError?.call(e.toString());
      pushError = e.toString();
      return PushResult(error: e.toString());
    } finally {
      final localHead = await _currentLocalHead(repo.id);
      await _recordSyncLog(
        repository: repo,
        remoteId: resolvedRemoteId,
        operation: 'push',
        status: pushError == null ? 'success' : 'failed',
        startedAt: startedAt,
        endedAt: DateTime.now(),
        totalFiles: pushedObjects,
        successCount: pushError == null ? pushedObjects : 0,
        failCount: pushError == null ? 0 : 1,
        errorMessage: pushError,
        remoteHeadCommitId: remoteHeadCommitId,
        localHeadCommitId: localHead,
      );
      _disconnect();
    }
  }

  Future<PullResult> pull(
    Repository repo, {
    String? remoteName,
    bool rebase = false,
  }) async {
    final startedAt = DateTime.now();
    String? resolvedRemoteId;
    String remoteHeadCommitId = '';
    int pulledObjects = 0;
    int pulledCommits = 0;
    String? pullError;
    try {
      final remote = await _getEffectiveRemote(repo, remoteName);
      if (remote == null) {
        pullError = 'No remote configured';
        return const PullResult(error: 'No remote configured');
      }

      final resolvedRemoteName = remote['remote_name'] as String? ?? '';
      resolvedRemoteId = await _resolveVcRemoteId(repo.id, resolvedRemoteName);

      final conn = await _getConnection(remote['remote_name'] as String);
      if (conn == null) {
        pullError = 'Remote connection not found';
        return const PullResult(error: 'Remote connection not found');
      }

      onProgress?.call(0.1, 'Fetching remote state...');

      final fetchResult = await fetch(
        repo,
        remoteName: remote['remote_name'] as String,
      );
      remoteHeadCommitId = fetchResult.remoteHead;
      pulledCommits = fetchResult.behind;

      if (fetchResult.behind == 0) {
        return const PullResult(success: true);
      }

      onProgress?.call(0.3, 'Downloading objects...');

      final objects = await _collectObjectsToPull(repo, fetchResult.remoteHead);

      for (final objectHash in objects) {
        final objectPath = p.join(
          repo.localPath,
          '.nanosync',
          'objects',
          objectHash,
        );
        final remoteObjectPath =
            '${remote['remote_path']}/.nanosync/objects/$objectHash';

        if (!await File(objectPath).exists()) {
          await _downloadFile(conn, remoteObjectPath, objectPath);
          pulledObjects++;
          onProgress?.call(
            0.3 + 0.4 * (pulledObjects / objects.length),
            'Downloading objects $pulledObjects/${objects.length}',
          );
        }
      }

      onProgress?.call(0.75, 'Merging changes...');

      final engine = VcEngine(repositoryId: repo.id, db: _vcDb);
      final status = await engine.status();
      final repoStatus = status.data as VcRepositoryStatus;

      List<String> conflicts = [];

      if (repoStatus.isClean || fetchResult.ahead == 0) {
        onProgress?.call(0.85, 'Fast-forwarding...');
        if (repoStatus.headCommitId.isNotEmpty) {
          await engine.reset(all: true, hard: true);
        }
      } else {
        onProgress?.call(0.85, 'Merging local changes...');
        conflicts = await _performMerge(repo, fetchResult.remoteHead, rebase);
      }

      onProgress?.call(0.95, 'Updating tracking...');

      final repoRemotes = await _db.getRepositoryRemotes(repo.id);
      for (final rr in repoRemotes) {
        if (rr['remote_name'] == remote['remote_name']) {
          await _db.updateRepositoryRemote(rr['id'] as String, {
            'last_sync': DateTime.now().toIso8601String(),
          });
          break;
        }
      }

      onProgress?.call(1.0, 'Pull complete');

      return PullResult(
        pulledCommits: fetchResult.behind,
        mergedFiles: [],
        conflicts: conflicts,
        success: conflicts.isEmpty,
      );
    } catch (e) {
      onError?.call(e.toString());
      pullError = e.toString();
      return PullResult(error: e.toString());
    } finally {
      final localHead = await _currentLocalHead(repo.id);
      await _recordSyncLog(
        repository: repo,
        remoteId: resolvedRemoteId,
        operation: 'pull',
        status: pullError == null ? 'success' : 'failed',
        startedAt: startedAt,
        endedAt: DateTime.now(),
        totalFiles: pulledObjects,
        successCount: pullError == null ? pulledObjects : 0,
        failCount: pullError == null ? 0 : 1,
        errorMessage: pullError,
        remoteHeadCommitId: remoteHeadCommitId,
        localHeadCommitId: localHead,
        behindCount: pulledCommits,
      );
      _disconnect();
    }
  }

  Future<SyncResult> sync(Repository repo, {String? remoteName}) async {
    final startedAt = DateTime.now();
    String? resolvedRemoteId;
    String? syncError;
    int pushedCommits = 0;
    int pulledCommits = 0;
    int pushedObjects = 0;
    int pulledObjects = 0;
    List<String> conflicts = [];
    try {
      final remote = await _getEffectiveRemote(repo, remoteName);
      if (remote != null) {
        final resolvedRemoteName = remote['remote_name'] as String? ?? '';
        resolvedRemoteId = await _resolveVcRemoteId(
          repo.id,
          resolvedRemoteName,
        );
      }

      final pushResult = await push(repo, remoteName: remoteName);
      pushedCommits = pushResult.pushedCommits;
      pushedObjects = pushResult.pushedObjects;

      if (!pushResult.success && pushResult.error != null) {
        if (!pushResult.error!.contains('Pull first')) {
          syncError = pushResult.error;
          return SyncResult(error: pushResult.error);
        }
      }

      final pullResult = await pull(repo, remoteName: remoteName);
      pulledCommits = pullResult.pulledCommits;
      conflicts = pullResult.conflicts;

      if (!pullResult.success) {
        syncError = pullResult.error;
        return SyncResult(
          pushedCommits: pushResult.pushedCommits,
          pushedObjects: pushResult.pushedObjects,
          conflicts: pullResult.conflicts,
          error: pullResult.error,
        );
      }

      return SyncResult(
        pushedCommits: pushResult.pushedCommits,
        pulledCommits: pullResult.pulledCommits,
        pushedObjects: pushResult.pushedObjects,
        pulledObjects: pulledObjects,
        success: true,
      );
    } catch (e) {
      syncError = e.toString();
      return SyncResult(error: e.toString());
    } finally {
      final localHead = await _currentLocalHead(repo.id);
      await _recordSyncLog(
        repository: repo,
        remoteId: resolvedRemoteId,
        operation: 'sync',
        status: syncError == null ? 'success' : 'failed',
        startedAt: startedAt,
        endedAt: DateTime.now(),
        totalFiles: pushedObjects + pulledObjects,
        successCount: syncError == null ? pushedObjects + pulledObjects : 0,
        failCount: syncError == null ? 0 : 1,
        conflictCount: conflicts.length,
        errorMessage: syncError,
        localHeadCommitId: localHead,
        aheadCount: pushedCommits,
        behindCount: pulledCommits,
      );
    }
  }

  Future<void> _recordSyncLog({
    required Repository repository,
    required String? remoteId,
    required String operation,
    required String status,
    required DateTime startedAt,
    required DateTime endedAt,
    required int totalFiles,
    required int successCount,
    required int failCount,
    int skipCount = 0,
    int conflictCount = 0,
    String? errorMessage,
    String preCommitId = '',
    String postCommitId = '',
    String remoteHeadCommitId = '',
    String localHeadCommitId = '',
    int aheadCount = 0,
    int behindCount = 0,
  }) async {
    final identity = DeviceIdentityResolver.resolve();
    await _vcSync.recordRepositorySync(
      repositoryId: repository.id,
      repositoryName: repository.name,
      remoteId: remoteId,
      syncOperation: operation,
      status: status,
      startedAt: startedAt,
      endedAt: endedAt,
      totalFiles: totalFiles,
      successCount: successCount,
      failCount: failCount,
      skipCount: skipCount,
      conflictCount: conflictCount,
      errorMessage: errorMessage,
      preCommitId: preCommitId,
      postCommitId: postCommitId,
      remoteHeadCommitId: remoteHeadCommitId,
      localHeadCommitId: localHeadCommitId,
      aheadCount: aheadCount,
      behindCount: behindCount,
      sourceDeviceFingerprint: identity.fingerprint,
      sourceDeviceName: identity.deviceName,
      sourceUsername: identity.username,
    );
  }

  Future<String> _currentLocalHead(String repositoryId) async {
    final repo = await _vcDb.getRepository(repositoryId);
    return repo?.headCommitId ?? '';
  }

  Future<String?> _resolveVcRemoteId(
    String repositoryId,
    String remoteName,
  ) async {
    if (remoteName.isEmpty) {
      return null;
    }

    final remotes = await _vcDb.getRemotesByRepository(repositoryId);
    for (final remote in remotes) {
      if ((remote['name'] as String?) == remoteName) {
        return remote['id'] as String?;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getEffectiveRemote(
    Repository repo,
    String? remoteName,
  ) async {
    if (remoteName != null) {
      return await _db.getRepositoryRemoteByName(repo.id, remoteName);
    }
    return await _db.getDefaultRepositoryRemote(repo.id);
  }

  Future<RemoteConnection?> _getConnection(String connectionName) async {
    return await _connManager.getConnectionByName(connectionName);
  }

  Future<void> _connect(RemoteConnection conn) async {
    if (conn.protocol.value == 'smb') {
      await _smb.connect(conn);
    } else if (conn.protocol.value == 'webdav') {
      await _webdav.connect(conn);
    }
    // UNC 不需要显式连接，使用 Windows 凭据自动处理
  }

  void _disconnect() {
    _smb.disconnect();
    _webdav.disconnect();
    // UNC 不需要显式断开连接
  }

  Future<void> _uploadFile(
    RemoteConnection conn,
    String localPath,
    String remotePath,
  ) async {
    if (conn.protocol.value == 'smb') {
      await _smb.uploadFile(conn, localPath, remotePath);
    } else if (conn.protocol.value == 'unc') {
      await _unc.uploadFile(conn, localPath, remotePath);
    } else if (conn.protocol.value == 'webdav') {
      await _webdav.uploadFile(conn, localPath, remotePath);
    }
  }

  Future<void> _downloadFile(
    RemoteConnection conn,
    String remotePath,
    String localPath,
  ) async {
    await File(localPath).parent.create(recursive: true);

    if (conn.protocol.value == 'smb') {
      await _smb.downloadFile(conn, remotePath, localPath);
    } else if (conn.protocol.value == 'unc') {
      await _unc.downloadFile(conn, remotePath, localPath);
    } else if (conn.protocol.value == 'webdav') {
      await _webdav.downloadFile(conn, remotePath, localPath);
    }
  }

  Future<Set<String>> _collectObjectsToPush(
    Repository repo,
    String remoteHead,
  ) async {
    final objects = <String>{};
    final vcRepo = await _vcDb.getRepository(repo.id);
    if (vcRepo == null || vcRepo.headCommitId.isEmpty) {
      return objects;
    }

    final commitsToPush = await _collectCommitsSince(
      repo.id,
      remoteHead,
      vcRepo.headCommitId,
    );

    for (final commitId in commitsToPush) {
      final treeEntries = await _vcDb.getTreeEntries(commitId);
      for (final entry in treeEntries) {
        if (entry.fileHash.isNotEmpty) {
          objects.add(entry.fileHash);
        }
      }
    }

    return objects;
  }

  Future<Set<String>> _collectObjectsToPull(
    Repository repo,
    String remoteHead,
  ) async {
    final objects = <String>{};
    final vcRepo = await _vcDb.getRepository(repo.id);
    final localHead = vcRepo?.headCommitId ?? '';

    final commitsToPull = await _collectCommitsSince(
      repo.id,
      localHead,
      remoteHead,
    );

    for (final commitId in commitsToPull) {
      final treeEntries = await _vcDb.getTreeEntries(commitId);
      for (final entry in treeEntries) {
        if (entry.fileHash.isNotEmpty) {
          objects.add(entry.fileHash);
        }
      }
    }

    return objects;
  }

  Future<List<String>> _collectCommitsSince(
    String repositoryId,
    String sinceCommitId,
    String untilCommitId,
  ) async {
    final commits = <String>[];
    final visited = <String>{};
    final queue = <String>[untilCommitId];

    while (queue.isNotEmpty) {
      final commitId = queue.removeAt(0);
      if (commitId.isEmpty || visited.contains(commitId)) continue;
      if (commitId == sinceCommitId) continue;

      visited.add(commitId);
      commits.add(commitId);

      final commit = await _vcDb.getCommit(commitId);
      if (commit != null) {
        if (commit.parentCommitId.isNotEmpty) {
          queue.add(commit.parentCommitId);
        }
        if (commit.secondParentId.isNotEmpty) {
          queue.add(commit.secondParentId);
        }
      }
    }

    return commits;
  }

  Future<List<String>> _performMerge(
    Repository repo,
    String remoteHead,
    bool rebase,
  ) async {
    final engine = VcEngine(repositoryId: repo.id, db: _vcDb);
    await engine.add(all: true);
    await engine.commit(message: 'WIP: Pre-merge commit');

    final treeEntries = await _vcDb.getTreeEntries(remoteHead);
    final objectsDir = p.join(repo.localPath, '.nanosync', 'objects');

    for (final entry in treeEntries) {
      final targetPath = p.join(repo.localPath, entry.relativePath);
      final objectPath = p.join(objectsDir, entry.fileHash);

      if (await File(objectPath).exists()) {
        await File(targetPath).parent.create(recursive: true);
        await File(objectPath).copy(targetPath);
      }
    }

    await _vcDb.updateRepository(repo.id, {
      'head_commit_id': remoteHead,
      'updated_at': DateTime.now().toIso8601String(),
    });

    return [];
  }
}
