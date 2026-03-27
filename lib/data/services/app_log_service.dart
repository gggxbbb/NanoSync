import '../models/app_log.dart';
import '../vc_database.dart';

class AppLogService {
  static AppLogService? _instance;
  final VcDatabase _db;

  AppLogService._({VcDatabase? db}) : _db = db ?? VcDatabase.instance;

  static AppLogService get instance {
    _instance ??= AppLogService._();
    return _instance!;
  }

  Future<void> write({
    required AppLogLevel level,
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    String stackTrace = '',
    Map<String, dynamic> context = const {},
  }) async {
    final log = AppLog.create(
      level: level,
      category: category,
      message: message,
      details: details,
      repositoryId: repositoryId,
      operation: operation,
      source: source,
      stackTrace: stackTrace,
      context: context,
    );
    await _db.insertAppLog(log.toMap());
  }

  Future<void> debug({
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    Map<String, dynamic> context = const {},
  }) {
    return write(
      level: AppLogLevel.debug,
      category: category,
      message: message,
      details: details,
      repositoryId: repositoryId,
      operation: operation,
      source: source,
      context: context,
    );
  }

  Future<void> info({
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    Map<String, dynamic> context = const {},
  }) {
    return write(
      level: AppLogLevel.info,
      category: category,
      message: message,
      details: details,
      repositoryId: repositoryId,
      operation: operation,
      source: source,
      context: context,
    );
  }

  Future<void> warning({
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    Map<String, dynamic> context = const {},
  }) {
    return write(
      level: AppLogLevel.warning,
      category: category,
      message: message,
      details: details,
      repositoryId: repositoryId,
      operation: operation,
      source: source,
      context: context,
    );
  }

  Future<void> error({
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    String stackTrace = '',
    Map<String, dynamic> context = const {},
  }) {
    return write(
      level: AppLogLevel.error,
      category: category,
      message: message,
      details: details,
      repositoryId: repositoryId,
      operation: operation,
      source: source,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<List<AppLog>> getLogs({
    int limit = 500,
    AppLogLevel? minLevel,
    String repositoryId = '',
  }) async {
    final records = await _db.getAppLogs(
      limit: limit,
      minLevel: minLevel?.name,
      repositoryId: repositoryId,
    );
    return records.map(AppLog.fromMap).toList();
  }

  Future<void> clearLogs() async {
    await _db.clearAllAppLogs();
  }
}
