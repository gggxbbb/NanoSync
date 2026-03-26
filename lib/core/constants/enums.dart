/// 同步方向枚举
enum SyncDirection {
  localToRemote('local_to_remote', '本地→远端'),
  remoteToLocal('remote_to_local', '远端→本地'),
  bidirectional('bidirectional', '双向同步'),
  mirror('mirror', '镜像同步');

  const SyncDirection(this.value, this.label);
  final String value;
  final String label;

  static SyncDirection fromValue(String value) {
    return SyncDirection.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncDirection.localToRemote,
    );
  }
}

/// 远端协议类型
enum RemoteProtocol {
  smb('smb', 'SMB'),
  webdav('webdav', 'WebDAV');

  const RemoteProtocol(this.value, this.label);
  final String value;
  final String label;

  static RemoteProtocol fromValue(String value) {
    return RemoteProtocol.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RemoteProtocol.smb,
    );
  }
}

/// 同步触发方式
enum SyncTrigger {
  manual('manual', '手动'),
  scheduled('scheduled', '定时'),
  realtime('realtime', '实时');

  const SyncTrigger(this.value, this.label);
  final String value;
  final String label;

  static SyncTrigger fromValue(String value) {
    return SyncTrigger.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncTrigger.manual,
    );
  }
}

/// 定时周期类型
enum ScheduleType {
  minutes('minutes', '分钟'),
  hours('hours', '小时'),
  days('days', '天'),
  weeks('weeks', '周'),
  months('months', '月');

  const ScheduleType(this.value, this.label);
  final String value;
  final String label;

  static ScheduleType fromValue(String value) {
    return ScheduleType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ScheduleType.hours,
    );
  }
}

/// 冲突处理策略
enum ConflictStrategy {
  localOverwrite('local_overwrite', '本地覆盖远端'),
  remoteOverwrite('remote_overwrite', '远端覆盖本地'),
  keepBoth('keep_both', '保留双方文件');

  const ConflictStrategy(this.value, this.label);
  final String value;
  final String label;

  static ConflictStrategy fromValue(String value) {
    return ConflictStrategy.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ConflictStrategy.keepBoth,
    );
  }
}

/// 任务状态
enum TaskStatus {
  idle('idle', '等待中'),
  syncing('syncing', '同步中'),
  paused('paused', '已暂停'),
  success('success', '同步成功'),
  failed('failed', '同步失败'),
  cancelled('cancelled', '已取消');

  const TaskStatus(this.value, this.label);
  final String value;
  final String label;

  static TaskStatus fromValue(String value) {
    return TaskStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TaskStatus.idle,
    );
  }
}

/// 文件变更类型
enum ChangeType {
  added('added', '新增'),
  modified('modified', '修改'),
  deleted('deleted', '删除'),
  renamed('renamed', '重命名'),
  moved('moved', '移动');

  const ChangeType(this.value, this.label);
  final String value;
  final String label;

  static ChangeType fromValue(String value) {
    return ChangeType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ChangeType.added,
    );
  }
}

/// 同步操作类型
enum SyncOperation {
  upload('upload', '上传'),
  download('download', '下载'),
  delete('delete', '删除'),
  rename('rename', '重命名'),
  skip('skip', '跳过'),
  conflict('conflict', '冲突');

  const SyncOperation(this.value, this.label);
  final String value;
  final String label;

  static SyncOperation fromValue(String value) {
    return SyncOperation.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncOperation.skip,
    );
  }
}

/// 主题模式
enum AppThemeMode {
  light('light', '浅色'),
  dark('dark', '深色'),
  system('system', '跟随系统');

  const AppThemeMode(this.value, this.label);
  final String value;
  final String label;

  static AppThemeMode fromValue(String value) {
    return AppThemeMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AppThemeMode.system,
    );
  }
}
