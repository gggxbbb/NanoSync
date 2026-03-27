/// 应用常量配置
class AppConstants {
  AppConstants._();

  // 应用信息
  static const String appName = 'NanoSync';
  static const String appVersion = '1.0.0';
  static const String appDescription = '本地文件夹与远端SMB/WebDAV同步工具';

  // 数据库
  static const String databaseName = 'nanosync.db';
  static const int databaseVersion = 2;

  // 版本存储
  static const String versionsFolder = '.nanosync_versions';
  static const int defaultMaxVersions = 10;
  static const int defaultMaxVersionDays = 30;
  static const int defaultMaxVersionSizeGB = 10;
  static const int defaultVersionMergeMinutes = 5;

  // 同步
  static const int defaultRetryCount = 3;
  static const int defaultRetryDelaySeconds = 5;
  static const int defaultRealtimeDelaySeconds = 3;
  static const int defaultConcurrentUploads = 3;
  static const int defaultBandwidthLimitKBps = 0; // 0 = 无限制
  static const int largeFileThresholdMB = 100;
  static const int chunkSizeMB = 10;

  // 排除规则
  static const List<String> defaultExcludeExtensions = [
    '.tmp',
    '.temp',
    '.bak',
    '.swp',
    '.lock',
    '.partial',
    '.crdownload',
    '.download',
  ];
  static const List<String> defaultExcludeFolders = [
    '.nanosync_versions',
    '.git',
    '.svn',
    '.hg',
    '__pycache__',
    'node_modules',
    '.idea',
    '.vscode',
    '\$RECYCLE.BIN',
    'System Volume Information',
  ];
  static const List<String> defaultExcludeFileNames = [
    'Thumbs.db',
    'desktop.ini',
    '.DS_Store',
  ];

  // 文件监听
  static const int fileWatcherDebounceMs = 500;

  // UI
  static const double sidebarWidth = 280.0;
  static const double minWindowWidth = 1024.0;
  static const double minWindowHeight = 640.0;

  // SharedPreferences keys
  static const String prefThemeMode = 'theme_mode';
  static const String prefUseMica = 'use_mica';
  static const String prefAutoStart = 'auto_start';
  static const String prefMinimizeToTray = 'minimize_to_tray';
  static const String prefDefaultConflictStrategy = 'default_conflict_strategy';
  static const String prefMaxVersions = 'max_versions';
  static const String prefMaxVersionDays = 'max_version_days';
  static const String prefMaxVersionSizeGB = 'max_version_size_gb';
  static const String prefVersionMergeMinutes = 'version_merge_minutes';
  static const String prefRetryCount = 'retry_count';
  static const String prefRetryDelay = 'retry_delay';
  static const String prefRealtimeDelay = 'realtime_delay';
  static const String prefBandwidthLimit = 'bandwidth_limit';
  static const String prefEncryptionKey = 'encryption_key';
}
