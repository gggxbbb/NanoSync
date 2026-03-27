import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models/vc_models.dart';

class VcDatabase {
  static VcDatabase? _instance;
  static Database? _database;

  VcDatabase._();

  static VcDatabase get instance {
    _instance ??= VcDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    final appDir = Directory.current.path;
    final dbDir = p.join(appDir, 'data');
    await Directory(dbDir).create(recursive: true);
    final dbPath = p.join(dbDir, 'nanosync_vc.db');

    return await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE vc_repositories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        current_branch_id TEXT NOT NULL DEFAULT '',
        head_commit_id TEXT NOT NULL DEFAULT '',
        is_initialized INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE vc_branches (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        name TEXT NOT NULL,
        commit_id TEXT NOT NULL DEFAULT '',
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_branches_repo ON vc_branches(repository_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_branches_name ON vc_branches(repository_id, name)
    ''');

    await db.execute('''
      CREATE TABLE vc_commits (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        parent_commit_id TEXT NOT NULL DEFAULT '',
        second_parent_id TEXT NOT NULL DEFAULT '',
        message TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_email TEXT NOT NULL,
        authored_at TEXT NOT NULL,
        committer_name TEXT NOT NULL,
        committer_email TEXT NOT NULL,
        committed_at TEXT NOT NULL,
        tree_hash TEXT NOT NULL DEFAULT '',
        file_count INTEGER NOT NULL DEFAULT 0,
        additions INTEGER NOT NULL DEFAULT 0,
        deletions INTEGER NOT NULL DEFAULT 0,
        is_merge INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE,
        FOREIGN KEY (branch_id) REFERENCES vc_branches(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_commits_repo ON vc_commits(repository_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_commits_branch ON vc_commits(branch_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_commits_parent ON vc_commits(parent_commit_id)
    ''');

    await db.execute('''
      CREATE TABLE vc_tree_entries (
        id TEXT PRIMARY KEY,
        commit_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        file_type TEXT NOT NULL DEFAULT 'file',
        file_size INTEGER NOT NULL DEFAULT 0,
        file_hash TEXT NOT NULL DEFAULT '',
        mode INTEGER NOT NULL DEFAULT 420,
        created_at TEXT NOT NULL,
        FOREIGN KEY (commit_id) REFERENCES vc_commits(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_tree_commit ON vc_tree_entries(commit_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_tree_path ON vc_tree_entries(commit_id, relative_path)
    ''');

    await db.execute('''
      CREATE TABLE vc_file_changes (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        commit_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        old_path TEXT NOT NULL DEFAULT '',
        change_type TEXT NOT NULL DEFAULT 'modified',
        status TEXT NOT NULL DEFAULT 'untracked',
        old_size INTEGER NOT NULL DEFAULT 0,
        new_size INTEGER NOT NULL DEFAULT 0,
        old_hash TEXT NOT NULL DEFAULT '',
        new_hash TEXT NOT NULL DEFAULT '',
        additions INTEGER NOT NULL DEFAULT 0,
        deletions INTEGER NOT NULL DEFAULT 0,
        is_binary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE,
        FOREIGN KEY (commit_id) REFERENCES vc_commits(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_changes_repo ON vc_file_changes(repository_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_changes_commit ON vc_file_changes(commit_id)
    ''');

    await db.execute('''
      CREATE TABLE vc_staging_entries (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        old_path TEXT NOT NULL DEFAULT '',
        change_type TEXT NOT NULL DEFAULT 'modified',
        old_size INTEGER NOT NULL DEFAULT 0,
        new_size INTEGER NOT NULL DEFAULT 0,
        old_hash TEXT NOT NULL DEFAULT '',
        new_hash TEXT NOT NULL DEFAULT '',
        is_staged INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_staging_repo ON vc_staging_entries(repository_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_staging_path ON vc_staging_entries(repository_id, relative_path)
    ''');

    await db.execute('''
      CREATE TABLE vc_stashes (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        branch_id TEXT NOT NULL DEFAULT '',
        message TEXT NOT NULL,
        commit_id TEXT NOT NULL DEFAULT '',
        file_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_stashes_repo ON vc_stashes(repository_id)
    ''');

    await db.execute('''
      CREATE TABLE vc_stash_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stash_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        old_path TEXT NOT NULL DEFAULT '',
        change_type TEXT NOT NULL DEFAULT 'modified',
        old_size INTEGER NOT NULL DEFAULT 0,
        new_size INTEGER NOT NULL DEFAULT 0,
        old_hash TEXT NOT NULL DEFAULT '',
        new_hash TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (stash_id) REFERENCES vc_stashes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_stash_entries_stash ON vc_stash_entries(stash_id)
    ''');

    await _createRemoteAndSyncTables(db);
    await _createAppLogTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createRemoteAndSyncTables(db);
    }
    if (oldVersion < 3) {
      await db.execute('DROP INDEX IF EXISTS idx_sync_records_repo');
      await db.execute('DROP TABLE IF EXISTS vc_sync_records');
      await _createRemoteAndSyncTables(db);
    }
    if (oldVersion < 4) {
      await _createAppLogTable(db);
    }
  }

  Future<void> _createRemoteAndSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vc_remotes (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        name TEXT NOT NULL,
        remote_key TEXT NOT NULL,
        protocol TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL DEFAULT '',
        remote_path TEXT NOT NULL,
        last_remote_head_commit_id TEXT NOT NULL DEFAULT '',
        last_local_head_commit_id TEXT NOT NULL DEFAULT '',
        last_sync_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_remotes_repo_key ON vc_remotes(repository_id, remote_key)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_remotes_repo ON vc_remotes(repository_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vc_sync_records (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        remote_id TEXT,
        repository_name TEXT NOT NULL,
        sync_operation TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        total_files INTEGER NOT NULL DEFAULT 0,
        success_count INTEGER NOT NULL DEFAULT 0,
        fail_count INTEGER NOT NULL DEFAULT 0,
        skip_count INTEGER NOT NULL DEFAULT 0,
        conflict_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        pre_commit_id TEXT NOT NULL DEFAULT '',
        post_commit_id TEXT NOT NULL DEFAULT '',
        remote_head_commit_id TEXT NOT NULL DEFAULT '',
        local_head_commit_id TEXT NOT NULL DEFAULT '',
        ahead_count INTEGER NOT NULL DEFAULT 0,
        behind_count INTEGER NOT NULL DEFAULT 0,
        source_device_fingerprint TEXT NOT NULL DEFAULT '',
        source_device_name TEXT NOT NULL DEFAULT '',
        source_username TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES vc_repositories(id) ON DELETE CASCADE,
        FOREIGN KEY (remote_id) REFERENCES vc_remotes(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_records_repo ON vc_sync_records(repository_id, created_at DESC)
    ''');
  }

  Future<void> _createAppLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vc_app_logs (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        repository_id TEXT NOT NULL DEFAULT '',
        operation TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        stack_trace TEXT NOT NULL DEFAULT '',
        context_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_logs_created_at ON vc_app_logs(created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_logs_level ON vc_app_logs(level, created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_logs_repo ON vc_app_logs(repository_id, created_at DESC)
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<int> insertRepository(Map<String, dynamic> repo) async {
    final db = await database;
    return await db.insert(
      'vc_repositories',
      repo,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRepository(String id, Map<String, dynamic> repo) async {
    final db = await database;
    return await db.update(
      'vc_repositories',
      repo,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepository(String id) async {
    final db = await database;
    return await db.delete('vc_repositories', where: 'id = ?', whereArgs: [id]);
  }

  Future<VcRepository?> getRepository(String id) async {
    final db = await database;
    final results = await db.query(
      'vc_repositories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? VcRepository.fromMap(results.first) : null;
  }

  Future<VcRepository?> getRepositoryByLocalPath(String localPath) async {
    final db = await database;
    final results = await db.query(
      'vc_repositories',
      where: 'local_path = ?',
      whereArgs: [localPath],
      limit: 1,
    );
    return results.isNotEmpty ? VcRepository.fromMap(results.first) : null;
  }

  Future<List<VcRepository>> getAllRepositories() async {
    final db = await database;
    final results = await db.query(
      'vc_repositories',
      orderBy: 'created_at DESC',
    );
    return results.map((m) => VcRepository.fromMap(m)).toList();
  }

  Future<int> insertBranch(Map<String, dynamic> branch) async {
    final db = await database;
    return await db.insert(
      'vc_branches',
      branch,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateBranch(String id, Map<String, dynamic> branch) async {
    final db = await database;
    return await db.update(
      'vc_branches',
      branch,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteBranch(String id) async {
    final db = await database;
    return await db.delete('vc_branches', where: 'id = ?', whereArgs: [id]);
  }

  Future<VcBranch?> getBranch(String id) async {
    final db = await database;
    final results = await db.query(
      'vc_branches',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? VcBranch.fromMap(results.first) : null;
  }

  Future<VcBranch?> getBranchByName(String repositoryId, String name) async {
    final db = await database;
    final results = await db.query(
      'vc_branches',
      where: 'repository_id = ? AND name = ?',
      whereArgs: [repositoryId, name],
    );
    return results.isNotEmpty ? VcBranch.fromMap(results.first) : null;
  }

  Future<List<VcBranch>> getBranches(String repositoryId) async {
    final db = await database;
    final results = await db.query(
      'vc_branches',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'created_at ASC',
    );
    return results.map((m) => VcBranch.fromMap(m)).toList();
  }

  Future<int> insertCommit(Map<String, dynamic> commit) async {
    final db = await database;
    return await db.insert(
      'vc_commits',
      commit,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateCommit(String id, Map<String, dynamic> commit) async {
    final db = await database;
    return await db.update(
      'vc_commits',
      commit,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<VcCommit?> getCommit(String id) async {
    final db = await database;
    final results = await db.query(
      'vc_commits',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? VcCommit.fromMap(results.first) : null;
  }

  Future<List<VcCommit>> getCommits(
    String repositoryId, {
    String? branchId,
    int? limit,
    String? since,
    String? until,
  }) async {
    final db = await database;

    String where = 'repository_id = ?';
    List<dynamic> whereArgs = [repositoryId];

    if (branchId != null) {
      where += ' AND branch_id = ?';
      whereArgs.add(branchId);
    }

    if (since != null) {
      where += ' AND committed_at >= ?';
      whereArgs.add(since);
    }

    if (until != null) {
      where += ' AND committed_at <= ?';
      whereArgs.add(until);
    }

    final results = await db.query(
      'vc_commits',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'committed_at DESC',
      limit: limit,
    );
    return results.map((m) => VcCommit.fromMap(m)).toList();
  }

  Future<int> insertTreeEntry(Map<String, dynamic> entry) async {
    final db = await database;
    return await db.insert(
      'vc_tree_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VcTreeEntry>> getTreeEntries(String commitId) async {
    final db = await database;
    final results = await db.query(
      'vc_tree_entries',
      where: 'commit_id = ?',
      whereArgs: [commitId],
    );
    return results.map((m) => VcTreeEntry.fromMap(m)).toList();
  }

  Future<int> insertFileChange(Map<String, dynamic> change) async {
    final db = await database;
    return await db.insert(
      'vc_file_changes',
      change,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VcFileChange>> getFileChangesByCommit(String commitId) async {
    final db = await database;
    final results = await db.query(
      'vc_file_changes',
      where: 'commit_id = ?',
      whereArgs: [commitId],
    );
    return results.map((m) => VcFileChange.fromMap(m)).toList();
  }

  Future<int> insertStagingEntry(Map<String, dynamic> entry) async {
    final db = await database;
    await db.delete(
      'vc_staging_entries',
      where: 'repository_id = ? AND relative_path = ?',
      whereArgs: [entry['repository_id'], entry['relative_path']],
    );
    return await db.insert(
      'vc_staging_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteStagingEntry(String id) async {
    final db = await database;
    return await db.delete(
      'vc_staging_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> clearStagingEntries(String repositoryId) async {
    final db = await database;
    return await db.delete(
      'vc_staging_entries',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
    );
  }

  Future<List<VcStagingEntry>> getStagingEntries(String repositoryId) async {
    final db = await database;
    final results = await db.query(
      'vc_staging_entries',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'relative_path ASC',
    );
    return results.map((m) => VcStagingEntry.fromMap(m)).toList();
  }

  Future<int> insertStash(Map<String, dynamic> stash) async {
    final db = await database;
    return await db.insert(
      'vc_stashes',
      stash,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteStash(String id) async {
    final db = await database;
    return await db.delete('vc_stashes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<VcStash>> getStashes(String repositoryId) async {
    final db = await database;
    final results = await db.query(
      'vc_stashes',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'created_at DESC',
    );
    return results.map((m) => VcStash.fromMap(m)).toList();
  }

  Future<int> insertStashEntry(Map<String, dynamic> entry) async {
    final db = await database;
    return await db.insert('vc_stash_entries', entry);
  }

  Future<List<Map<String, dynamic>>> getStashEntries(String stashId) async {
    final db = await database;
    return await db.query(
      'vc_stash_entries',
      where: 'stash_id = ?',
      whereArgs: [stashId],
    );
  }

  Future<int> insertRemote(Map<String, dynamic> remote) async {
    final db = await database;
    return await db.insert(
      'vc_remotes',
      remote,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRemote(String id, Map<String, dynamic> remote) async {
    final db = await database;
    return await db.update(
      'vc_remotes',
      remote,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getRemote(String id) async {
    final db = await database;
    final results = await db.query(
      'vc_remotes',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getRemoteByKey(
    String repositoryId,
    String remoteKey,
  ) async {
    final db = await database;
    final results = await db.query(
      'vc_remotes',
      where: 'repository_id = ? AND remote_key = ?',
      whereArgs: [repositoryId, remoteKey],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getRemotesByRepository(
    String repositoryId,
  ) async {
    final db = await database;
    return await db.query(
      'vc_remotes',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'created_at ASC',
    );
  }

  Future<int> insertSyncRecord(Map<String, dynamic> record) async {
    final db = await database;
    return await db.insert(
      'vc_sync_records',
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSyncRecordsByRepository(
    String repositoryId, {
    int limit = 200,
  }) async {
    final db = await database;
    return await db.query(
      'vc_sync_records',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getAllSyncRecords({
    int limit = 200,
  }) async {
    final db = await database;
    return await db.query(
      'vc_sync_records',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<int> clearAllSyncRecords() async {
    final db = await database;
    return await db.delete('vc_sync_records');
  }

  Future<int> insertAppLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert(
      'vc_app_logs',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAppLogs({
    int limit = 500,
    String? minLevel,
    String repositoryId = '',
  }) async {
    final db = await database;
    final levels = <String>['debug', 'info', 'warning', 'error'];
    final minIndex = minLevel == null ? 0 : levels.indexOf(minLevel);

    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (minIndex > 0) {
      final accepted = levels.sublist(minIndex);
      whereParts.add(
        'level IN (${List.filled(accepted.length, '?').join(', ')})',
      );
      whereArgs.addAll(accepted);
    }

    if (repositoryId.isNotEmpty) {
      whereParts.add('repository_id = ?');
      whereArgs.add(repositoryId);
    }

    final where = whereParts.isEmpty ? null : whereParts.join(' AND ');
    return await db.query(
      'vc_app_logs',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<int> clearAllAppLogs() async {
    final db = await database;
    return await db.delete('vc_app_logs');
  }
}
