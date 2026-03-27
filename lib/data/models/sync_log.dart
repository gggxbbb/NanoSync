/// 同步日志模型
class SyncLog {
  final String id;
  final String repositoryId;
  final String repositoryName;
  final DateTime startTime;
  DateTime? endTime;
  int totalFiles;
  int successCount;
  int failCount;
  int skipCount;
  int conflictCount;
  String status;
  String? errorMessage;
  final String sourceDeviceFingerprint;
  final String sourceDeviceName;
  final String sourceUsername;
  List<LogEntry> entries;

  SyncLog({
    String? id,
    required this.repositoryId,
    required this.repositoryName,
    DateTime? startTime,
    this.endTime,
    this.totalFiles = 0,
    this.successCount = 0,
    this.failCount = 0,
    this.skipCount = 0,
    this.conflictCount = 0,
    this.status = 'running',
    this.errorMessage,
    this.sourceDeviceFingerprint = '',
    this.sourceDeviceName = '',
    this.sourceUsername = '',
    List<LogEntry>? entries,
  })  : id = id ?? _generateId(),
        startTime = startTime ?? DateTime.now(),
        entries = entries ?? [];

  static String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().microsecond % 1000).toRadixString(36);
  }

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  String get durationText {
    final d = duration;
    if (d == null) return '进行中';
    if (d.inSeconds < 60) return '${d.inSeconds}秒';
    if (d.inMinutes < 60) return '${d.inMinutes}分${d.inSeconds % 60}秒';
    return '${d.inHours}时${d.inMinutes % 60}分';
  }

  factory SyncLog.fromMap(Map<String, dynamic> map) {
    return SyncLog(
      id: map['id'] as String,
      repositoryId: (map['repository_id'] ?? map['task_id']) as String,
      repositoryName: (map['repository_name'] ?? map['task_name']) as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      totalFiles: map['total_files'] as int? ?? 0,
      successCount: map['success_count'] as int? ?? 0,
      failCount: map['fail_count'] as int? ?? 0,
      skipCount: map['skip_count'] as int? ?? 0,
      conflictCount: map['conflict_count'] as int? ?? 0,
      status: map['status'] as String? ?? 'running',
      errorMessage: map['error_message'] as String?,
      sourceDeviceFingerprint:
          map['source_device_fingerprint'] as String? ?? '',
      sourceDeviceName: map['source_device_name'] as String? ?? '',
      sourceUsername: map['source_username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'repository_name': repositoryName,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'total_files': totalFiles,
      'success_count': successCount,
      'fail_count': failCount,
      'skip_count': skipCount,
      'conflict_count': conflictCount,
      'status': status,
      'error_message': errorMessage,
      'source_device_fingerprint': sourceDeviceFingerprint,
      'source_device_name': sourceDeviceName,
      'source_username': sourceUsername,
    };
  }
}

/// 日志条目
class LogEntry {
  final String filePath;
  final String operation;
  final String status;
  final String? detail;
  final DateTime time;

  LogEntry({
    required this.filePath,
    required this.operation,
    required this.status,
    this.detail,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      filePath: map['file_path'] as String,
      operation: map['operation'] as String,
      status: map['status'] as String,
      detail: map['detail'] as String?,
      time: DateTime.parse(map['time'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'file_path': filePath,
      'operation': operation,
      'status': status,
      'detail': detail,
      'time': time.toIso8601String(),
    };
  }
}
