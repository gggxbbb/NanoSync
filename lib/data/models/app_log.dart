import 'dart:convert';

enum AppLogLevel { debug, info, warning, error }

class AppLog {
  final String id;
  final DateTime createdAt;
  final AppLogLevel level;
  final String category;
  final String message;
  final String details;
  final String repositoryId;
  final String operation;
  final String source;
  final String stackTrace;
  final Map<String, dynamic> context;

  const AppLog({
    required this.id,
    required this.createdAt,
    required this.level,
    required this.category,
    required this.message,
    this.details = '',
    this.repositoryId = '',
    this.operation = '',
    this.source = '',
    this.stackTrace = '',
    this.context = const {},
  });

  factory AppLog.create({
    required AppLogLevel level,
    required String category,
    required String message,
    String details = '',
    String repositoryId = '',
    String operation = '',
    String source = '',
    String stackTrace = '',
    Map<String, dynamic> context = const {},
  }) {
    return AppLog(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      createdAt: DateTime.now(),
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
  }

  factory AppLog.fromMap(Map<String, dynamic> map) {
    return AppLog(
      id: map['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      level: _levelFromString(map['level'] as String? ?? 'info'),
      category: map['category'] as String? ?? '',
      message: map['message'] as String? ?? '',
      details: map['details'] as String? ?? '',
      repositoryId: map['repository_id'] as String? ?? '',
      operation: map['operation'] as String? ?? '',
      source: map['source'] as String? ?? '',
      stackTrace: map['stack_trace'] as String? ?? '',
      context: _decodeContext(map['context_json'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'level': level.name,
      'category': category,
      'message': message,
      'details': details,
      'repository_id': repositoryId,
      'operation': operation,
      'source': source,
      'stack_trace': stackTrace,
      'context_json': jsonEncode(context),
    };
  }

  static AppLogLevel _levelFromString(String value) {
    return AppLogLevel.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppLogLevel.info,
    );
  }

  static Map<String, dynamic> _decodeContext(String? value) {
    if (value == null || value.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, val) => MapEntry('$key', val));
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }
}
