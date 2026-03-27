// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'NanoSync';

  @override
  String get navRepositories => '仓库';

  @override
  String get navRemoteConnections => '远程连接';

  @override
  String get navVersionControl => '版本控制';

  @override
  String get navSyncLogs => '同步日志';

  @override
  String get navSettings => '系统设置';

  @override
  String get navAbout => '关于';

  @override
  String get deviceLabel => '设备';

  @override
  String get userLabel => '用户';

  @override
  String get fingerprintLabel => '指纹';

  @override
  String get unknownDevice => '未知设备';

  @override
  String get unknownUser => '未知用户';

  @override
  String titleBarDeviceTooltip(
    Object deviceLabel,
    Object deviceName,
    Object userLabel,
    Object username,
    Object fingerprintLabel,
    Object fingerprint,
  ) {
    return '$deviceLabel: $deviceName\n$userLabel: $username\n$fingerprintLabel: $fingerprint';
  }

  @override
  String titleBarDeviceBadge(
    Object deviceName,
    Object username,
    Object shortFingerprint,
  ) {
    return '$deviceName/$username#$shortFingerprint';
  }

  @override
  String get repositoriesPageTitle => '仓库';

  @override
  String get addRepository => '添加仓库';

  @override
  String get clone => '克隆';

  @override
  String get searchRepositories => '搜索仓库...';

  @override
  String get noRepositoriesRegistered => '尚无已注册仓库';

  @override
  String get noRepositoriesMatch => '没有仓库匹配搜索条件';

  @override
  String commitsAhead(int count) {
    return '$count 个提交领先';
  }

  @override
  String commitsBehind(int count) {
    return '$count 个提交落后';
  }

  @override
  String get fetch => '获取';

  @override
  String get sync => '同步';

  @override
  String get addRepositoryDialogTitle => '添加仓库';

  @override
  String get localPath => '本地路径';

  @override
  String get selectFolder => '选择文件夹...';

  @override
  String get browse => '浏览';

  @override
  String get repositoryName => '仓库名称';

  @override
  String get enterName => '输入名称...';

  @override
  String get createInitialCommit => '创建初始提交';

  @override
  String get remoteConfiguration => '远程配置（可选）';

  @override
  String get connection => '连接';

  @override
  String get selectConnection => '选择连接...';

  @override
  String get remotePath => '远程路径';

  @override
  String get remotePathPlaceholder => '/path/to/repository';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get remoteConnectionsPageTitle => '远程连接';

  @override
  String get newConnection => '新建连接';

  @override
  String get noRemoteConnectionsConfigured => '尚未配置远程连接';

  @override
  String get addConnection => '添加连接';

  @override
  String get testingConnection => '正在测试连接';

  @override
  String get connectionSuccessful => '连接成功';

  @override
  String get connectionFailed => '连接失败';

  @override
  String successfullyConnectedTo(Object address) {
    return '成功连接到 $address';
  }

  @override
  String get error => '错误';

  @override
  String get unknownError => '未知错误';

  @override
  String get ok => '确定';

  @override
  String get deleteConnection => '删除连接';

  @override
  String deleteConnectionConfirm(Object name) {
    return '确定要删除\"$name\"吗？';
  }

  @override
  String get test => '测试';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get editConnection => '编辑连接';

  @override
  String get newConnectionDialog => '新建连接';

  @override
  String get name => '名称';

  @override
  String get nameExample => '例如：nas-backup';

  @override
  String get protocol => '协议';

  @override
  String get smb => 'SMB';

  @override
  String get webdav => 'WebDAV';

  @override
  String get host => '主机';

  @override
  String get hostExample => '例如：192.168.1.100';

  @override
  String get port => '端口';

  @override
  String get username => '用户名（可选）';

  @override
  String get usernameExample => '留空则使用游客访问';

  @override
  String get password => '密码（可选）';

  @override
  String get save => '保存';

  @override
  String get validationError => '验证错误';

  @override
  String get nameRequired => '名称为必填项';

  @override
  String get hostRequired => '主机为必填项';

  @override
  String get settingsPageTitle => '系统设置';

  @override
  String get appearance => '外观';

  @override
  String get themeMode => '主题模式';

  @override
  String get themeDescription => '选择应用的主题外观';

  @override
  String get followSystem => '跟随系统';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get mica => '云母特效';

  @override
  String get micaDescription => '启用Windows 11风格的云母/亚克力背景效果';

  @override
  String get system => '系统';

  @override
  String get autoStart => '开机自启';

  @override
  String get autoStartDescription => 'Windows启动时自动运行应用';

  @override
  String get minimizeToTray => '最小化到托盘';

  @override
  String get minimizeToTrayDescription => '关闭窗口时最小化到系统托盘而非退出';

  @override
  String get versionManagement => '版本管理';

  @override
  String get maxVersionCount => '保留版本数';

  @override
  String get maxVersionCountDescription => '每个文件保留的最大版本数量';

  @override
  String get maxVersionDays => '保留天数';

  @override
  String get maxVersionDaysDescription => '版本文件的保留天数';

  @override
  String get maxVersionSize => '容量限制';

  @override
  String get maxVersionSizeDescription => '版本存储的最大容量（GB）';

  @override
  String get syncSettings => '同步设置';

  @override
  String get retryCount => '重试次数';

  @override
  String get retryCountDescription => '同步失败时的重试次数';

  @override
  String get retryDelay => '重试间隔';

  @override
  String get retryDelayDescription => '重试之间的等待时间（秒）';

  @override
  String get realtimeDelay => '实时同步延迟';

  @override
  String get realtimeDelayDescription => '实时同步的文件变更延迟（秒）';

  @override
  String get dataManagement => '数据管理';

  @override
  String get exportConfig => '导出配置';

  @override
  String get importConfig => '导入配置';

  @override
  String get openSourceInfo => '开源信息';

  @override
  String get githubRepository => 'GitHub 仓库';

  @override
  String get authorHomepage => '作者主页';

  @override
  String get dependencies => '开源依赖';

  @override
  String get syncLogsPageTitle => '同步日志';

  @override
  String get refresh => '刷新';

  @override
  String get clearLogs => '清空';

  @override
  String get searchLogs => '搜索日志...';

  @override
  String get noLogs => '暂无日志';

  @override
  String get noLogsDescription => '执行同步任务后日志将显示在这里';

  @override
  String get deletedRepository => '已删除的仓库';

  @override
  String get deleted => '已删除';

  @override
  String get success => '成功';

  @override
  String get failed => '失败';

  @override
  String get inProgress => '进行中';

  @override
  String successFailCount(int success, int failed) {
    return '成功: $success 失败: $failed';
  }

  @override
  String sourceDevice(Object device, Object user) {
    return '来源: $device / $user';
  }

  @override
  String get syncInRepositoryPage => '仓库同步请在\\\"仓库\\\"页面执行';

  @override
  String get startTime => '开始时间';

  @override
  String get endTime => '结束时间';

  @override
  String get inProgress2 => '进行中';

  @override
  String get totalDuration => '总耗时';

  @override
  String get totalFiles => '总文件数';

  @override
  String get errorMessage => '错误信息:';

  @override
  String get confirmClearLogs => '确认清空';

  @override
  String get clearLogsConfirm => '确定要清空所有同步日志吗？此操作不可恢复。';

  @override
  String get versionControlPageTitle => '版本控制';

  @override
  String get selectSyncTask => '请先选择一个同步任务';

  @override
  String get initializeRepository => '初始化版本库';

  @override
  String get uninitialized => '未初始化';

  @override
  String changesCount(int count) {
    return '$count 个更改';
  }

  @override
  String get branches => '分支';

  @override
  String get stash => 'Stash';

  @override
  String conflicts(int count) {
    return '冲突($count)';
  }

  @override
  String fileDiff(Object path) {
    return '文件差异: $path';
  }

  @override
  String get initialCommitNoDiff => '初始提交暂不支持父提交对比';

  @override
  String commitDiff(Object id) {
    return '提交差异: $id';
  }

  @override
  String get noChangeDetected => '该提交未检测到可展示差异';

  @override
  String workingDiff(Object path) {
    return '工作区差异: $path';
  }

  @override
  String get noWorkingDiff => '该文件当前没有可展示差异';

  @override
  String get stageDiffNotAvailable => '该文件暂无可展示的差异，请先暂存后重试';

  @override
  String get close => '关闭';

  @override
  String get aboutPageTitle => '关于';

  @override
  String get mainFeatures => '主要功能';

  @override
  String get mitLicense => 'MIT 许可证';

  @override
  String get mitLicenseInfo => '本软件遵循MIT开源协议';

  @override
  String get feature1 => '本地文件夹与SMB/WebDAV远端同步';

  @override
  String get feature2 => '默认双向同步，支持一键切换仅本地模式';

  @override
  String get feature3 => '文件版本管理与恢复';

  @override
  String get feature4 => '定时同步与实时文件监听';

  @override
  String get feature5 => '冲突检测与智能处理';

  @override
  String get feature6 => '系统托盘集成，后台静默运行';
}
