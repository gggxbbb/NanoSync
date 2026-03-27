import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/constants/app_constants.dart';

/// SQLite数据库管理器
class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    final dbPath = await _getDbPath();
    return await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// 获取数据库文件路径
  Future<String> _getDbPath() async {
    final appDir = Directory.current.path;
    final dbDir = p.join(appDir, 'data');
    await Directory(dbDir).create(recursive: true);
    return p.join(dbDir, AppConstants.databaseName);
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    await _createRepositoryCoreTables(db);
    await _createRepositoryLocalSettingsTable(db);
    await _createSyncLogTables(db);
  }

  Future<void> _createRepositoryLocalSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repository_local_settings (
        repository_id TEXT PRIMARY KEY,
        max_versions INTEGER NOT NULL DEFAULT 10,
        max_version_days INTEGER NOT NULL DEFAULT 30,
        max_version_size_gb INTEGER NOT NULL DEFAULT 10,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES registered_repositories(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createRepositoryCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS registered_repositories (
        id TEXT PRIMARY KEY,
        local_path TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        last_accessed TEXT,
        added_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repos_path ON registered_repositories(local_path)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repos_name ON registered_repositories(name)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_connections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        protocol TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL DEFAULT '',
        password TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_connections_name ON remote_connections(name)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS repository_remotes (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        remote_name TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        last_sync TEXT,
        last_fetch TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES registered_repositories(id) ON DELETE CASCADE,
        FOREIGN KEY (remote_name) REFERENCES remote_connections(name) ON DELETE CASCADE,
        UNIQUE(repository_id, remote_name)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repo_remotes_repo ON repository_remotes(repository_id)',
    );
  }

  Future<void> _createSyncLogTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_logs (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        task_name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        total_files INTEGER NOT NULL DEFAULT 0,
        success_count INTEGER NOT NULL DEFAULT 0,
        fail_count INTEGER NOT NULL DEFAULT 0,
        skip_count INTEGER NOT NULL DEFAULT 0,
        conflict_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'running',
        error_message TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_logs_task_id ON sync_logs(task_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_logs_start_time ON sync_logs(start_time)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS log_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        operation TEXT NOT NULL,
        status TEXT NOT NULL,
        detail TEXT,
        time TEXT NOT NULL,
        FOREIGN KEY (log_id) REFERENCES sync_logs(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_log_entries_log_id ON log_entries(log_id)',
    );
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await _createRepositoryCoreTables(db);
      await _createRepositoryLocalSettingsTable(db);

      await db.execute('DROP TABLE IF EXISTS log_entries');
      await db.execute('DROP TABLE IF EXISTS sync_logs');
      await _createSyncLogTables(db);

      await db.execute('DROP INDEX IF EXISTS idx_snapshots_relative_path');
      await db.execute('DROP INDEX IF EXISTS idx_snapshots_task_id');
      await db.execute('DROP TABLE IF EXISTS file_snapshots');

      await db.execute('DROP INDEX IF EXISTS idx_tasks_target_id');
      await db.execute('DROP TABLE IF EXISTS sync_tasks');

      await db.execute('DROP INDEX IF EXISTS idx_targets_name');
      await db.execute('DROP TABLE IF EXISTS sync_targets');
    }

    if (oldVersion < 5) {
      await _createRepositoryLocalSettingsTable(db);
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ========== 同步日志 CRUD ==========

  Future<int> insertLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert(
      'sync_logs',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateLog(String id, Map<String, dynamic> log) async {
    final db = await database;
    return await db.update('sync_logs', log, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getLogsByTask(String taskId) async {
    final db = await database;
    return await db.query(
      'sync_logs',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'start_time DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllLogs({int limit = 200}) async {
    final db = await database;
    return await db.query(
      'sync_logs',
      orderBy: 'start_time DESC',
      limit: limit,
    );
  }

  Future<int> clearAllLogs() async {
    final db = await database;
    return await db.transaction((txn) async {
      await txn.delete('log_entries');
      return await txn.delete('sync_logs');
    });
  }

  Future<int> clearLogsByTask(String taskId) async {
    final db = await database;
    final logs = await getLogsByTask(taskId);
    for (final log in logs) {
      await db.delete(
        'log_entries',
        where: 'log_id = ?',
        whereArgs: [log['id']],
      );
    }
    return await db.delete(
      'sync_logs',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  // ========== 日志条目 CRUD ==========

  Future<void> insertLogEntries(
    String logId,
    List<Map<String, dynamic>> entries,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert('log_entries', {...entry, 'log_id': logId});
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getLogEntries(String logId) async {
    final db = await database;
    return await db.query(
      'log_entries',
      where: 'log_id = ?',
      whereArgs: [logId],
      orderBy: 'time ASC',
    );
  }

  // ========== 注册仓库 CRUD ==========

  Future<int> insertRegisteredRepository(
    Map<String, dynamic> repository,
  ) async {
    final db = await database;
    return await db.insert(
      'registered_repositories',
      repository,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRegisteredRepository(
    String id,
    Map<String, dynamic> repository,
  ) async {
    final db = await database;
    return await db.update(
      'registered_repositories',
      repository,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRegisteredRepository(String id) async {
    final db = await database;
    return await db.delete(
      'registered_repositories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> upsertRepositoryLocalSettings(
    Map<String, dynamic> settings,
  ) async {
    final db = await database;
    return await db.insert(
      'repository_local_settings',
      settings,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getRepositoryLocalSettings(
    String repositoryId,
  ) async {
    final db = await database;
    final results = await db.query(
      'repository_local_settings',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> deleteRepositoryLocalSettings(String repositoryId) async {
    final db = await database;
    return await db.delete(
      'repository_local_settings',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
    );
  }

  Future<Map<String, dynamic>?> getRegisteredRepository(String id) async {
    final db = await database;
    final results = await db.query(
      'registered_repositories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getRegisteredRepositoryByPath(
    String localPath,
  ) async {
    final db = await database;
    final results = await db.query(
      'registered_repositories',
      where: 'local_path = ?',
      whereArgs: [localPath],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllRegisteredRepositories() async {
    final db = await database;
    return await db.query('registered_repositories', orderBy: 'added_at DESC');
  }

  // ========== 远程连接 CRUD ==========

  Future<int> insertRemoteConnection(Map<String, dynamic> connection) async {
    final db = await database;
    return await db.insert(
      'remote_connections',
      connection,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRemoteConnection(
    String id,
    Map<String, dynamic> connection,
  ) async {
    final db = await database;
    return await db.update(
      'remote_connections',
      connection,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRemoteConnection(String id) async {
    final db = await database;
    return await db.delete(
      'remote_connections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getRemoteConnection(String id) async {
    final db = await database;
    final results = await db.query(
      'remote_connections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getRemoteConnectionByName(String name) async {
    final db = await database;
    final results = await db.query(
      'remote_connections',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllRemoteConnections() async {
    final db = await database;
    return await db.query('remote_connections', orderBy: 'created_at DESC');
  }

  // ========== 仓库远程绑定 CRUD ==========

  Future<int> insertRepositoryRemote(
    Map<String, dynamic> repositoryRemote,
  ) async {
    final db = await database;
    return await db.insert(
      'repository_remotes',
      repositoryRemote,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRepositoryRemote(
    String id,
    Map<String, dynamic> repositoryRemote,
  ) async {
    final db = await database;
    return await db.update(
      'repository_remotes',
      repositoryRemote,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepositoryRemote(String id) async {
    final db = await database;
    return await db.delete(
      'repository_remotes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepositoryRemotesByRepository(String repositoryId) async {
    final db = await database;
    return await db.delete(
      'repository_remotes',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
    );
  }

  Future<List<Map<String, dynamic>>> getRepositoryRemotes(
    String repositoryId,
  ) async {
    final db = await database;
    return await db.query(
      'repository_remotes',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'is_default DESC, created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getRepositoryRemoteByName(
    String repositoryId,
    String remoteName,
  ) async {
    final db = await database;
    final results = await db.query(
      'repository_remotes',
      where: 'repository_id = ? AND remote_name = ?',
      whereArgs: [repositoryId, remoteName],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getDefaultRepositoryRemote(
    String repositoryId,
  ) async {
    final db = await database;
    final results = await db.query(
      'repository_remotes',
      where: 'repository_id = ? AND is_default = 1',
      whereArgs: [repositoryId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> setDefaultRepositoryRemote(
    String repositoryId,
    String remoteName,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'repository_remotes',
        {'is_default': 0},
        where: 'repository_id = ?',
        whereArgs: [repositoryId],
      );
      await txn.update(
        'repository_remotes',
        {'is_default': 1},
        where: 'repository_id = ? AND remote_name = ?',
        whereArgs: [repositoryId, remoteName],
      );
    });
  }
}
