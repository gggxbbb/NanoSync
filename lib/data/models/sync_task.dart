import 'package:uuid/uuid.dart';
import '../../core/constants/enums.dart';

/// 同步任务数据模型
class SyncTask {
  final String id;
  String name;
  String localPath;
  String? targetId;
  RemoteProtocol remoteProtocol;
  String remoteHost;
  int remotePort;
  String remoteUsername;
  String remotePassword;
  String remotePath;
  SyncDirection syncDirection;
  SyncTrigger syncTrigger;
  ScheduleType? scheduleType;
  int? scheduleInterval;
  String? scheduleTime;
  int? scheduleDayOfWeek;
  int? scheduleDayOfMonth;
  int realtimeDelaySeconds;
  ConflictStrategy conflictStrategy;
  bool isEnabled;
  bool isRunning;
  TaskStatus status;
  DateTime? lastSyncTime;
  DateTime? nextSyncTime;
  String? lastError;
  double syncProgress;
  List<String> excludeExtensions;
  List<String> excludeFolders;
  List<String> excludePatterns;
  int bandwidthLimitKBps;
  int retryCount;
  int retryDelaySeconds;
  DateTime createdAt;
  DateTime updatedAt;

  SyncTask({
    String? id,
    required this.name,
    required this.localPath,
    this.targetId,
    this.remoteProtocol = RemoteProtocol.smb,
    required this.remoteHost,
    this.remotePort = 445,
    required this.remoteUsername,
    this.remotePassword = '',
    required this.remotePath,
    this.syncDirection = SyncDirection.bidirectional,
    this.syncTrigger = SyncTrigger.manual,
    this.scheduleType,
    this.scheduleInterval,
    this.scheduleTime,
    this.scheduleDayOfWeek,
    this.scheduleDayOfMonth,
    this.realtimeDelaySeconds = 3,
    this.conflictStrategy = ConflictStrategy.keepBoth,
    this.isEnabled = true,
    this.isRunning = false,
    this.status = TaskStatus.idle,
    this.lastSyncTime,
    this.nextSyncTime,
    this.lastError,
    this.syncProgress = 0.0,
    List<String>? excludeExtensions,
    List<String>? excludeFolders,
    List<String>? excludePatterns,
    this.bandwidthLimitKBps = 0,
    this.retryCount = 3,
    this.retryDelaySeconds = 5,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       excludeExtensions = excludeExtensions ?? [],
       excludeFolders = excludeFolders ?? [],
       excludePatterns = excludePatterns ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 从数据库Map创建实例
  factory SyncTask.fromMap(Map<String, dynamic> map) {
    final rawDirection = SyncDirection.fromValue(
      map['sync_direction'] as String,
    );
    final normalizedDirection = rawDirection == SyncDirection.localOnly
        ? SyncDirection.localOnly
        : SyncDirection.bidirectional;

    return SyncTask(
      id: map['id'] as String,
      name: map['name'] as String,
      localPath: map['local_path'] as String,
      targetId: map['target_id'] as String?,
      remoteProtocol: RemoteProtocol.fromValue(
        map['remote_protocol'] as String,
      ),
      remoteHost: map['remote_host'] as String,
      remotePort: map['remote_port'] as int,
      remoteUsername: map['remote_username'] as String,
      remotePassword: map['remote_password'] as String? ?? '',
      remotePath: map['remote_path'] as String,
      syncDirection: normalizedDirection,
      syncTrigger: SyncTrigger.fromValue(map['sync_trigger'] as String),
      scheduleType: map['schedule_type'] != null
          ? ScheduleType.fromValue(map['schedule_type'] as String)
          : null,
      scheduleInterval: map['schedule_interval'] as int?,
      scheduleTime: map['schedule_time'] as String?,
      scheduleDayOfWeek: map['schedule_day_of_week'] as int?,
      scheduleDayOfMonth: map['schedule_day_of_month'] as int?,
      realtimeDelaySeconds: map['realtime_delay_seconds'] as int? ?? 3,
      conflictStrategy: ConflictStrategy.fromValue(
        map['conflict_strategy'] as String,
      ),
      isEnabled: (map['is_enabled'] as int) == 1,
      isRunning: (map['is_running'] as int) == 1,
      status: TaskStatus.fromValue(map['status'] as String),
      lastSyncTime: map['last_sync_time'] != null
          ? DateTime.parse(map['last_sync_time'] as String)
          : null,
      nextSyncTime: map['next_sync_time'] != null
          ? DateTime.parse(map['next_sync_time'] as String)
          : null,
      lastError: map['last_error'] as String?,
      syncProgress: (map['sync_progress'] as num?)?.toDouble() ?? 0.0,
      excludeExtensions: map['exclude_extensions'] != null
          ? (map['exclude_extensions'] as String)
                .split(',')
                .where((e) => e.isNotEmpty)
                .toList()
          : [],
      excludeFolders: map['exclude_folders'] != null
          ? (map['exclude_folders'] as String)
                .split(',')
                .where((e) => e.isNotEmpty)
                .toList()
          : [],
      excludePatterns: map['exclude_patterns'] != null
          ? (map['exclude_patterns'] as String)
                .split(',')
                .where((e) => e.isNotEmpty)
                .toList()
          : [],
      bandwidthLimitKBps: map['bandwidth_limit_kbps'] as int? ?? 0,
      retryCount: map['retry_count'] as int? ?? 3,
      retryDelaySeconds: map['retry_delay_seconds'] as int? ?? 5,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// 转换为数据库Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'local_path': localPath,
      'target_id': targetId,
      'remote_protocol': remoteProtocol.value,
      'remote_host': remoteHost,
      'remote_port': remotePort,
      'remote_username': remoteUsername,
      'remote_password': remotePassword,
      'remote_path': remotePath,
      'sync_direction': syncDirection.value,
      'sync_trigger': syncTrigger.value,
      'schedule_type': scheduleType?.value,
      'schedule_interval': scheduleInterval,
      'schedule_time': scheduleTime,
      'schedule_day_of_week': scheduleDayOfWeek,
      'schedule_day_of_month': scheduleDayOfMonth,
      'realtime_delay_seconds': realtimeDelaySeconds,
      'conflict_strategy': conflictStrategy.value,
      'is_enabled': isEnabled ? 1 : 0,
      'is_running': isRunning ? 1 : 0,
      'status': status.value,
      'last_sync_time': lastSyncTime?.toIso8601String(),
      'next_sync_time': nextSyncTime?.toIso8601String(),
      'last_error': lastError,
      'sync_progress': syncProgress,
      'exclude_extensions': excludeExtensions.join(','),
      'exclude_folders': excludeFolders.join(','),
      'exclude_patterns': excludePatterns.join(','),
      'bandwidth_limit_kbps': bandwidthLimitKBps,
      'retry_count': retryCount,
      'retry_delay_seconds': retryDelaySeconds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// 复制并修改
  SyncTask copyWith({
    String? name,
    String? localPath,
    String? targetId,
    RemoteProtocol? remoteProtocol,
    String? remoteHost,
    int? remotePort,
    String? remoteUsername,
    String? remotePassword,
    String? remotePath,
    SyncDirection? syncDirection,
    SyncTrigger? syncTrigger,
    ScheduleType? scheduleType,
    int? scheduleInterval,
    String? scheduleTime,
    int? scheduleDayOfWeek,
    int? scheduleDayOfMonth,
    int? realtimeDelaySeconds,
    ConflictStrategy? conflictStrategy,
    bool? isEnabled,
    bool? isRunning,
    TaskStatus? status,
    DateTime? lastSyncTime,
    DateTime? nextSyncTime,
    String? lastError,
    double? syncProgress,
    List<String>? excludeExtensions,
    List<String>? excludeFolders,
    List<String>? excludePatterns,
    int? bandwidthLimitKBps,
    int? retryCount,
    int? retryDelaySeconds,
  }) {
    return SyncTask(
      id: id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      targetId: targetId ?? this.targetId,
      remoteProtocol: remoteProtocol ?? this.remoteProtocol,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      remoteUsername: remoteUsername ?? this.remoteUsername,
      remotePassword: remotePassword ?? this.remotePassword,
      remotePath: remotePath ?? this.remotePath,
      syncDirection: syncDirection ?? this.syncDirection,
      syncTrigger: syncTrigger ?? this.syncTrigger,
      scheduleType: scheduleType ?? this.scheduleType,
      scheduleInterval: scheduleInterval ?? this.scheduleInterval,
      scheduleTime: scheduleTime ?? this.scheduleTime,
      scheduleDayOfWeek: scheduleDayOfWeek ?? this.scheduleDayOfWeek,
      scheduleDayOfMonth: scheduleDayOfMonth ?? this.scheduleDayOfMonth,
      realtimeDelaySeconds: realtimeDelaySeconds ?? this.realtimeDelaySeconds,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      isEnabled: isEnabled ?? this.isEnabled,
      isRunning: isRunning ?? this.isRunning,
      status: status ?? this.status,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      nextSyncTime: nextSyncTime ?? this.nextSyncTime,
      lastError: lastError ?? this.lastError,
      syncProgress: syncProgress ?? this.syncProgress,
      excludeExtensions: excludeExtensions ?? this.excludeExtensions,
      excludeFolders: excludeFolders ?? this.excludeFolders,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      bandwidthLimitKBps: bandwidthLimitKBps ?? this.bandwidthLimitKBps,
      retryCount: retryCount ?? this.retryCount,
      retryDelaySeconds: retryDelaySeconds ?? this.retryDelaySeconds,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() => 'SyncTask($name, ${status.label})';
}
