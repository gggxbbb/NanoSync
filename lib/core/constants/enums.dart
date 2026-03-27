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
