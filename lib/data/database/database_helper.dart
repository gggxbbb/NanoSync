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
      CREATE TABLE sync_targets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        remote_protocol TEXT NOT NULL DEFAULT 'smb',
        remote_host TEXT NOT NULL,
        remote_port INTEGER NOT NULL DEFAULT 445,
        remote_username TEXT NOT NULL DEFAULT '',
        remote_password TEXT NOT NULL DEFAULT '',
        remote_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_targets_name ON sync_targets(name)
    ''');

    await db.execute('''
      CREATE TABLE sync_tasks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        target_id TEXT,
        remote_protocol TEXT NOT NULL DEFAULT 'smb',
        remote_host TEXT NOT NULL,
        remote_port INTEGER NOT NULL DEFAULT 445,
        remote_username TEXT NOT NULL,
        remote_password TEXT NOT NULL DEFAULT '',
        remote_path TEXT NOT NULL,
        sync_direction TEXT NOT NULL DEFAULT 'bidirectional',
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
        updated_at TEXT NOT NULL,
        FOREIGN KEY (target_id) REFERENCES sync_targets(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_tasks_target_id ON sync_tasks(target_id)
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
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_targets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          remote_protocol TEXT NOT NULL DEFAULT 'smb',
          remote_host TEXT NOT NULL,
          remote_port INTEGER NOT NULL DEFAULT 445,
          remote_username TEXT NOT NULL DEFAULT '',
          remote_password TEXT NOT NULL DEFAULT '',
          remote_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_targets_name ON sync_targets(name)',
      );

      final taskColumns = await db.rawQuery('PRAGMA table_info(sync_tasks)');
      final hasTargetId = taskColumns.any((c) => c['name'] == 'target_id');
      if (!hasTargetId) {
        await db.execute('ALTER TABLE sync_tasks ADD COLUMN target_id TEXT');
      }

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_target_id ON sync_tasks(target_id)',
      );

      final tasks = await db.query('sync_tasks');
      final migratedTargetMap = <String, String>{};

      for (final task in tasks) {
        final syncDirection = task['sync_direction'] as String? ?? '';
        if (syncDirection == 'local_only') {
          continue;
        }

        final host = (task['remote_host'] as String?)?.trim() ?? '';
        if (host.isEmpty) {
          continue;
        }

        final protocol = task['remote_protocol'] as String? ?? 'smb';
        final port = (task['remote_port'] as int?) ?? 445;
        final username = task['remote_username'] as String? ?? '';
        final password = task['remote_password'] as String? ?? '';
        final key = '$protocol|$host|$port|$username|$password';

        String targetId;
        if (migratedTargetMap.containsKey(key)) {
          targetId = migratedTargetMap[key]!;
        } else {
          targetId = _generateId();
          final now = DateTime.now().toIso8601String();
          final defaultName = '$host:$port';

          await db.insert('sync_targets', {
            'id': targetId,
            'name': defaultName,
            'remote_protocol': protocol,
            'remote_host': host,
            'remote_port': port,
            'remote_username': username,
            'remote_password': password,
            'remote_path': '/',
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          migratedTargetMap[key] = targetId;
        }

        await db.update(
          'sync_tasks',
          {'target_id': targetId},
          where: 'id = ?',
          whereArgs: [task['id']],
        );
      }
    }
  }

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now.toRadixString(36);
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
    return await db.insert(
      'sync_tasks',
      task,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateTask(String id, Map<String, dynamic> task) async {
    final db = await database;
    return await db.update(
      'sync_tasks',
      task,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTask(String id) async {
    final db = await database;
    return await db.delete('sync_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getTask(String id) async {
    final db = await database;
    final results = await db.query(
      'sync_tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    return await db.query('sync_tasks', orderBy: 'created_at DESC');
  }

  // ========== 同步目标 CRUD ==========

  Future<int> insertTarget(Map<String, dynamic> target) async {
    final db = await database;
    return await db.insert(
      'sync_targets',
      target,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateTarget(String id, Map<String, dynamic> target) async {
    final db = await database;
    return await db.update(
      'sync_targets',
      target,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTarget(String id) async {
    final db = await database;
    await db.update(
      'sync_tasks',
      {'target_id': null},
      where: 'target_id = ?',
      whereArgs: [id],
    );
    return await db.delete('sync_targets', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getTarget(String id) async {
    final db = await database;
    final results = await db.query(
      'sync_targets',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllTargets() async {
    final db = await database;
    return await db.query('sync_targets', orderBy: 'created_at DESC');
  }

  Future<int> countTasksByTarget(String targetId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_tasks WHERE target_id = ?',
      [targetId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  // ========== 文件快照 CRUD ==========

  Future<int> insertSnapshot(Map<String, dynamic> snapshot) async {
    final db = await database;
    return await db.insert(
      'file_snapshots',
      snapshot,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSnapshotsBatch(
    List<Map<String, dynamic>> snapshots,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final snapshot in snapshots) {
      batch.insert(
        'file_snapshots',
        snapshot,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteSnapshotsByTask(String taskId) async {
    final db = await database;
    return await db.delete(
      'file_snapshots',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  Future<List<Map<String, dynamic>>> getSnapshotsByTask(String taskId) async {
    final db = await database;
    return await db.query(
      'file_snapshots',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  Future<Map<String, dynamic>?> getSnapshotByPath(
    String taskId,
    String relativePath,
  ) async {
    final db = await database;
    final results = await db.query(
      'file_snapshots',
      where: 'task_id = ? AND relative_path = ?',
      whereArgs: [taskId, relativePath],
    );
    return results.isNotEmpty ? results.first : null;
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
}
