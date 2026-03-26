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
    await db.execute('''
      CREATE TABLE sync_tasks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_protocol TEXT NOT NULL DEFAULT 'smb',
        remote_host TEXT NOT NULL,
        remote_port INTEGER NOT NULL DEFAULT 445,
        remote_username TEXT NOT NULL,
        remote_password TEXT NOT NULL DEFAULT '',
        remote_path TEXT NOT NULL,
        sync_direction TEXT NOT NULL DEFAULT 'local_to_remote',
        sync_trigger TEXT NOT NULL DEFAULT 'manual',
        schedule_type TEXT,
        schedule_interval INTEGER,
        schedule_time TEXT,
        schedule_day_of_week INTEGER,
        schedule_day_of_month INTEGER,
        realtime_delay_seconds INTEGER NOT NULL DEFAULT 3,
        conflict_strategy TEXT NOT NULL DEFAULT 'keep_both',
        is_enabled INTEGER NOT NULL DEFAULT 1,
        is_running INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'idle',
        last_sync_time TEXT,
        next_sync_time TEXT,
        last_error TEXT,
        sync_progress REAL NOT NULL DEFAULT 0.0,
        exclude_extensions TEXT NOT NULL DEFAULT '',
        exclude_folders TEXT NOT NULL DEFAULT '',
        exclude_patterns TEXT NOT NULL DEFAULT '',
        bandwidth_limit_kbps INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 3,
        retry_delay_seconds INTEGER NOT NULL DEFAULT 5,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE file_snapshots (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        absolute_path TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        last_modified TEXT NOT NULL,
        crc32 TEXT NOT NULL DEFAULT '',
        sha256 TEXT NOT NULL DEFAULT '',
        is_directory INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES sync_tasks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_snapshots_task_id ON file_snapshots(task_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_snapshots_relative_path ON file_snapshots(task_id, relative_path)
    ''');

    await db.execute('''
      CREATE TABLE file_versions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        original_path TEXT NOT NULL,
        version_path TEXT NOT NULL,
        version_name TEXT NOT NULL,
        version_number INTEGER NOT NULL DEFAULT 1,
        file_size INTEGER NOT NULL DEFAULT 0,
        crc32 TEXT NOT NULL DEFAULT '',
        operation_type TEXT NOT NULL DEFAULT 'modify',
        created_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES sync_tasks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_versions_task_id ON file_versions(task_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_versions_original_path ON file_versions(task_id, original_path)
    ''');

    await db.execute('''
      CREATE TABLE sync_logs (
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
        error_message TEXT,
        FOREIGN KEY (task_id) REFERENCES sync_tasks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_logs_task_id ON sync_logs(task_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_logs_start_time ON sync_logs(start_time)
    ''');

    await db.execute('''
      CREATE TABLE log_entries (
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

    await db.execute('''
      CREATE INDEX idx_log_entries_log_id ON log_entries(log_id)
    ''');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级时使用
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ========== 同步任务 CRUD ==========

  Future<int> insertTask(Map<String, dynamic> task) async {
    final db = await database;
    return await db.insert('sync_tasks', task,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateTask(String id, Map<String, dynamic> task) async {
    final db = await database;
    return await db
        .update('sync_tasks', task, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTask(String id) async {
    final db = await database;
    return await db.delete('sync_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getTask(String id) async {
    final db = await database;
    final results =
        await db.query('sync_tasks', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    return await db.query('sync_tasks', orderBy: 'created_at DESC');
  }

  // ========== 文件快照 CRUD ==========

  Future<int> insertSnapshot(Map<String, dynamic> snapshot) async {
    final db = await database;
    return await db.insert('file_snapshots', snapshot,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertSnapshotsBatch(
      List<Map<String, dynamic>> snapshots) async {
    final db = await database;
    final batch = db.batch();
    for (final snapshot in snapshots) {
      batch.insert('file_snapshots', snapshot,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteSnapshotsByTask(String taskId) async {
    final db = await database;
    return await db
        .delete('file_snapshots', where: 'task_id = ?', whereArgs: [taskId]);
  }

  Future<List<Map<String, dynamic>>> getSnapshotsByTask(String taskId) async {
    final db = await database;
    return await db
        .query('file_snapshots', where: 'task_id = ?', whereArgs: [taskId]);
  }

  Future<Map<String, dynamic>?> getSnapshotByPath(
      String taskId, String relativePath) async {
    final db = await database;
    final results = await db.query('file_snapshots',
        where: 'task_id = ? AND relative_path = ?',
        whereArgs: [taskId, relativePath]);
    return results.isNotEmpty ? results.first : null;
  }

  // ========== 版本记录 CRUD ==========

  Future<int> insertVersion(Map<String, dynamic> version) async {
    final db = await database;
    return await db.insert('file_versions', version,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteVersion(String id) async {
    final db = await database;
    return await db.delete('file_versions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getVersionsByTask(String taskId) async {
    final db = await database;
    return await db.query('file_versions',
        where: 'task_id = ?', whereArgs: [taskId], orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getVersionsByPath(
      String taskId, String originalPath) async {
    final db = await database;
    return await db.query('file_versions',
        where: 'task_id = ? AND original_path = ?',
        whereArgs: [taskId, originalPath],
        orderBy: 'version_number DESC');
  }

  Future<int> getLatestVersionNumber(String taskId, String originalPath) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(version_number) as max_version FROM file_versions WHERE task_id = ? AND original_path = ?',
      [taskId, originalPath],
    );
    return (result.first['max_version'] as int?) ?? 0;
  }

  Future<int> deleteVersionsOlderThan(String taskId, DateTime date) async {
    final db = await database;
    return await db.delete('file_versions',
        where: 'task_id = ? AND created_at < ?',
        whereArgs: [taskId, date.toIso8601String()]);
  }

  Future<int> deleteVersionsBeyondCount(
      String taskId, String originalPath, int maxCount) async {
    final db = await database;
    final versions = await db.query('file_versions',
        where: 'task_id = ? AND original_path = ?',
        whereArgs: [taskId, originalPath],
        orderBy: 'version_number DESC');
    if (versions.length <= maxCount) return 0;
    final toDelete = versions.sublist(maxCount);
    int deleted = 0;
    for (final v in toDelete) {
      deleted += await db
          .delete('file_versions', where: 'id = ?', whereArgs: [v['id']]);
    }
    return deleted;
  }

  // ========== 同步日志 CRUD ==========

  Future<int> insertLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert('sync_logs', log,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateLog(String id, Map<String, dynamic> log) async {
    final db = await database;
    return await db.update('sync_logs', log, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getLogsByTask(String taskId) async {
    final db = await database;
    return await db.query('sync_logs',
        where: 'task_id = ?', whereArgs: [taskId], orderBy: 'start_time DESC');
  }

  Future<List<Map<String, dynamic>>> getAllLogs({int limit = 200}) async {
    final db = await database;
    return await db.query('sync_logs',
        orderBy: 'start_time DESC', limit: limit);
  }

  Future<int> clearAllLogs() async {
    final db = await database;
    await db.delete('log_entries');
    return await db.delete('sync_logs');
  }

  Future<int> clearLogsByTask(String taskId) async {
    final db = await database;
    final logs = await getLogsByTask(taskId);
    for (final log in logs) {
      await db
          .delete('log_entries', where: 'log_id = ?', whereArgs: [log['id']]);
    }
    return await db
        .delete('sync_logs', where: 'task_id = ?', whereArgs: [taskId]);
  }

  // ========== 日志条目 CRUD ==========

  Future<void> insertLogEntries(
      String logId, List<Map<String, dynamic>> entries) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert('log_entries', {...entry, 'log_id': logId});
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getLogEntries(String logId) async {
    final db = await database;
    return await db.query('log_entries',
        where: 'log_id = ?', whereArgs: [logId], orderBy: 'time ASC');
  }
}
