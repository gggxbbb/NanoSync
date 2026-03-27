import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/automation_models.dart';

class AutomationService {
  static AutomationService? _instance;
  final DatabaseHelper _db;

  AutomationService._({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  static AutomationService get instance {
    _instance ??= AutomationService._();
    return _instance!;
  }

  /// Initialize automation tables in database
  Future<void> initializeAutomationTables() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS automation_rules (
        id TEXT PRIMARY KEY,
        repository_id TEXT NOT NULL,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        trigger_type INTEGER NOT NULL,
        action_type INTEGER NOT NULL,
        interval_minutes INTEGER,
        auto_commit_on_interval INTEGER DEFAULT 0,
        auto_push_on_interval INTEGER DEFAULT 0,
        commit_on_change INTEGER DEFAULT 0,
        push_after_commit INTEGER DEFAULT 0,
        debounce_seconds INTEGER,
        commit_message_template TEXT,
        created_at TEXT NOT NULL,
        last_triggered_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (repository_id) REFERENCES registered_repositories(id)
      )
    ''');
  }

  /// Create or update an automation rule
  Future<AutomationRule> saveAutomationRule(AutomationRule rule) async {
    final db = await _db.database;
    final data = rule.toMap();

    await db.insert(
      'automation_rules',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return rule;
  }

  /// Get all automation rules for a repository
  Future<List<AutomationRule>> getAutomationRulesByRepository(
    String repositoryId,
  ) async {
    final db = await _db.database;
    final maps = await db.query(
      'automation_rules',
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
      orderBy: 'created_at DESC',
    );

    return List<AutomationRule>.from(
      maps.map((x) => AutomationRule.fromMap(x)),
    );
  }

  /// Get a single automation rule by ID
  Future<AutomationRule?> getAutomationRuleById(String id) async {
    final db = await _db.database;
    final maps = await db.query(
      'automation_rules',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return AutomationRule.fromMap(maps.first);
  }

  /// Delete an automation rule
  Future<void> deleteAutomationRule(String id) async {
    final db = await _db.database;
    await db.delete('automation_rules', where: 'id = ?', whereArgs: [id]);
  }

  /// Update the last triggered timestamp
  Future<void> updateLastTriggered(String id) async {
    final db = await _db.database;
    await db.update(
      'automation_rules',
      {
        'last_triggered_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Enable or disable an automation rule
  Future<void> setAutomationRuleEnabled(String id, bool enabled) async {
    final db = await _db.database;
    await db.update(
      'automation_rules',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all enabled automation rules
  Future<List<AutomationRule>> getAllEnabledRules() async {
    final db = await _db.database;
    final maps = await db.query(
      'automation_rules',
      where: 'enabled = 1',
      orderBy: 'updated_at DESC',
    );

    return List<AutomationRule>.from(
      maps.map((x) => AutomationRule.fromMap(x)),
    );
  }

  /// Resolve commit message template with variables
  String resolveCommitMessageTemplate(
    String template, {
    required String repositoryName,
    required int fileCount,
    required int additions,
    required int deletions,
  }) {
    var resolved = template
        .replaceAll('{repo_name}', repositoryName)
        .replaceAll('{file_count}', fileCount.toString())
        .replaceAll('{additions}', additions.toString())
        .replaceAll('{deletions}', deletions.toString())
        .replaceAll('{timestamp}', DateTime.now().toIso8601String())
        .replaceAll('{date}', DateTime.now().toString().split(' ')[0]);

    // If template is empty or all variables, provide a sensible default
    if (resolved.isEmpty ||
        resolved.contains('{') ||
        resolved.trim().length < 2) {
      resolved =
          'Auto commit: $fileCount files changed, +$additions -$deletions';
    }

    return resolved;
  }
}
