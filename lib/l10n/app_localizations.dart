import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('zh')];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'NanoSync'**
  String get appTitle;

  /// No description provided for @navRepositories.
  ///
  /// In zh, this message translates to:
  /// **'仓库'**
  String get navRepositories;

  /// No description provided for @navRemoteConnections.
  ///
  /// In zh, this message translates to:
  /// **'远程连接'**
  String get navRemoteConnections;

  /// No description provided for @navVersionControl.
  ///
  /// In zh, this message translates to:
  /// **'版本控制'**
  String get navVersionControl;

  /// No description provided for @navSyncLogs.
  ///
  /// In zh, this message translates to:
  /// **'同步日志'**
  String get navSyncLogs;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'系统设置'**
  String get navSettings;

  /// No description provided for @navAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get navAbout;

  /// No description provided for @deviceLabel.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get deviceLabel;

  /// No description provided for @userLabel.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get userLabel;

  /// No description provided for @fingerprintLabel.
  ///
  /// In zh, this message translates to:
  /// **'指纹'**
  String get fingerprintLabel;

  /// No description provided for @unknownDevice.
  ///
  /// In zh, this message translates to:
  /// **'未知设备'**
  String get unknownDevice;

  /// No description provided for @unknownUser.
  ///
  /// In zh, this message translates to:
  /// **'未知用户'**
  String get unknownUser;

  /// No description provided for @titleBarDeviceTooltip.
  ///
  /// In zh, this message translates to:
  /// **'{deviceLabel}: {deviceName}\n{userLabel}: {username}\n{fingerprintLabel}: {fingerprint}'**
  String titleBarDeviceTooltip(
    Object deviceLabel,
    Object deviceName,
    Object userLabel,
    Object username,
    Object fingerprintLabel,
    Object fingerprint,
  );

  /// No description provided for @titleBarDeviceBadge.
  ///
  /// In zh, this message translates to:
  /// **'{deviceName}/{username}#{shortFingerprint}'**
  String titleBarDeviceBadge(
    Object deviceName,
    Object username,
    Object shortFingerprint,
  );

  /// No description provided for @repositoriesPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'仓库'**
  String get repositoriesPageTitle;

  /// No description provided for @addRepository.
  ///
  /// In zh, this message translates to:
  /// **'添加仓库'**
  String get addRepository;

  /// No description provided for @clone.
  ///
  /// In zh, this message translates to:
  /// **'克隆'**
  String get clone;

  /// No description provided for @searchRepositories.
  ///
  /// In zh, this message translates to:
  /// **'搜索仓库...'**
  String get searchRepositories;

  /// No description provided for @noRepositoriesRegistered.
  ///
  /// In zh, this message translates to:
  /// **'尚无已注册仓库'**
  String get noRepositoriesRegistered;

  /// No description provided for @noRepositoriesMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有仓库匹配搜索条件'**
  String get noRepositoriesMatch;

  /// No description provided for @commitsAhead.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个提交领先'**
  String commitsAhead(int count);

  /// No description provided for @commitsBehind.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个提交落后'**
  String commitsBehind(int count);

  /// No description provided for @fetch.
  ///
  /// In zh, this message translates to:
  /// **'获取'**
  String get fetch;

  /// No description provided for @sync.
  ///
  /// In zh, this message translates to:
  /// **'同步'**
  String get sync;

  /// No description provided for @addRepositoryDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加仓库'**
  String get addRepositoryDialogTitle;

  /// No description provided for @localPath.
  ///
  /// In zh, this message translates to:
  /// **'本地路径'**
  String get localPath;

  /// No description provided for @selectFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择文件夹...'**
  String get selectFolder;

  /// No description provided for @browse.
  ///
  /// In zh, this message translates to:
  /// **'浏览'**
  String get browse;

  /// No description provided for @repositoryName.
  ///
  /// In zh, this message translates to:
  /// **'仓库名称'**
  String get repositoryName;

  /// No description provided for @enterName.
  ///
  /// In zh, this message translates to:
  /// **'输入名称...'**
  String get enterName;

  /// No description provided for @createInitialCommit.
  ///
  /// In zh, this message translates to:
  /// **'创建初始提交'**
  String get createInitialCommit;

  /// No description provided for @ignoreConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'忽略配置（可选）'**
  String get ignoreConfiguration;

  /// No description provided for @ignorePatterns.
  ///
  /// In zh, this message translates to:
  /// **'忽略模式'**
  String get ignorePatterns;

  /// No description provided for @ignorePatternsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如: *.log, .env (逗号分隔)'**
  String get ignorePatternsPlaceholder;

  /// No description provided for @ignoreExtensions.
  ///
  /// In zh, this message translates to:
  /// **'忽略扩展名'**
  String get ignoreExtensions;

  /// No description provided for @ignoreExtensionsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如: .log, .tmp (逗号分隔)'**
  String get ignoreExtensionsPlaceholder;

  /// No description provided for @ignoreFolders.
  ///
  /// In zh, this message translates to:
  /// **'忽略文件夹'**
  String get ignoreFolders;

  /// No description provided for @ignoreFoldersPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'例如: node_modules, build (逗号分隔)'**
  String get ignoreFoldersPlaceholder;

  /// No description provided for @remoteConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'远程配置（可选）'**
  String get remoteConfiguration;

  /// No description provided for @connection.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get connection;

  /// No description provided for @selectConnection.
  ///
  /// In zh, this message translates to:
  /// **'选择连接...'**
  String get selectConnection;

  /// No description provided for @remotePath.
  ///
  /// In zh, this message translates to:
  /// **'远程路径'**
  String get remotePath;

  /// No description provided for @remotePathPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'/path/to/repository'**
  String get remotePathPlaceholder;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @remoteConnectionsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'远程连接'**
  String get remoteConnectionsPageTitle;

  /// No description provided for @newConnection.
  ///
  /// In zh, this message translates to:
  /// **'新建连接'**
  String get newConnection;

  /// No description provided for @noRemoteConnectionsConfigured.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置远程连接'**
  String get noRemoteConnectionsConfigured;

  /// No description provided for @addConnection.
  ///
  /// In zh, this message translates to:
  /// **'添加连接'**
  String get addConnection;

  /// No description provided for @testingConnection.
  ///
  /// In zh, this message translates to:
  /// **'正在测试连接'**
  String get testingConnection;

  /// No description provided for @connectionSuccessful.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get connectionSuccessful;

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get connectionFailed;

  /// No description provided for @successfullyConnectedTo.
  ///
  /// In zh, this message translates to:
  /// **'成功连接到 {address}'**
  String successfullyConnectedTo(Object address);

  /// No description provided for @error.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get error;

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get unknownError;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @deleteConnection.
  ///
  /// In zh, this message translates to:
  /// **'删除连接'**
  String get deleteConnection;

  /// No description provided for @deleteConnectionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除\"{name}\"吗？'**
  String deleteConnectionConfirm(Object name);

  /// No description provided for @test.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get test;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @editConnection.
  ///
  /// In zh, this message translates to:
  /// **'编辑连接'**
  String get editConnection;

  /// No description provided for @newConnectionDialog.
  ///
  /// In zh, this message translates to:
  /// **'新建连接'**
  String get newConnectionDialog;

  /// No description provided for @name.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get name;

  /// No description provided for @nameExample.
  ///
  /// In zh, this message translates to:
  /// **'例如：nas-backup'**
  String get nameExample;

  /// No description provided for @protocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get protocol;

  /// No description provided for @smb.
  ///
  /// In zh, this message translates to:
  /// **'SMB'**
  String get smb;

  /// No description provided for @webdav.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV'**
  String get webdav;

  /// No description provided for @host.
  ///
  /// In zh, this message translates to:
  /// **'主机'**
  String get host;

  /// No description provided for @hostExample.
  ///
  /// In zh, this message translates to:
  /// **'例如：192.168.1.100'**
  String get hostExample;

  /// No description provided for @port.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get port;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名（可选）'**
  String get username;

  /// No description provided for @usernameExample.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用游客访问'**
  String get usernameExample;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码（可选）'**
  String get password;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @validationError.
  ///
  /// In zh, this message translates to:
  /// **'验证错误'**
  String get validationError;

  /// No description provided for @nameRequired.
  ///
  /// In zh, this message translates to:
  /// **'名称为必填项'**
  String get nameRequired;

  /// No description provided for @hostRequired.
  ///
  /// In zh, this message translates to:
  /// **'主机为必填项'**
  String get hostRequired;

  /// No description provided for @settingsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'系统设置'**
  String get settingsPageTitle;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get themeMode;

  /// No description provided for @themeDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择应用的主题外观'**
  String get themeDescription;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @light.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get dark;

  /// No description provided for @mica.
  ///
  /// In zh, this message translates to:
  /// **'云母特效'**
  String get mica;

  /// No description provided for @micaDescription.
  ///
  /// In zh, this message translates to:
  /// **'启用Windows 11风格的云母/亚克力背景效果'**
  String get micaDescription;

  /// No description provided for @system.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get system;

  /// No description provided for @autoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启'**
  String get autoStart;

  /// No description provided for @autoStartDescription.
  ///
  /// In zh, this message translates to:
  /// **'Windows启动时自动运行应用'**
  String get autoStartDescription;

  /// No description provided for @minimizeToTray.
  ///
  /// In zh, this message translates to:
  /// **'最小化到托盘'**
  String get minimizeToTray;

  /// No description provided for @minimizeToTrayDescription.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时最小化到系统托盘而非退出'**
  String get minimizeToTrayDescription;

  /// No description provided for @versionManagement.
  ///
  /// In zh, this message translates to:
  /// **'版本管理'**
  String get versionManagement;

  /// No description provided for @maxVersionCount.
  ///
  /// In zh, this message translates to:
  /// **'保留版本数'**
  String get maxVersionCount;

  /// No description provided for @maxVersionCountDescription.
  ///
  /// In zh, this message translates to:
  /// **'每个文件保留的最大版本数量'**
  String get maxVersionCountDescription;

  /// No description provided for @maxVersionDays.
  ///
  /// In zh, this message translates to:
  /// **'保留天数'**
  String get maxVersionDays;

  /// No description provided for @maxVersionDaysDescription.
  ///
  /// In zh, this message translates to:
  /// **'版本文件的保留天数'**
  String get maxVersionDaysDescription;

  /// No description provided for @maxVersionSize.
  ///
  /// In zh, this message translates to:
  /// **'容量限制'**
  String get maxVersionSize;

  /// No description provided for @maxVersionSizeDescription.
  ///
  /// In zh, this message translates to:
  /// **'版本存储的最大容量（GB）'**
  String get maxVersionSizeDescription;

  /// No description provided for @syncSettings.
  ///
  /// In zh, this message translates to:
  /// **'同步设置'**
  String get syncSettings;

  /// No description provided for @retryCount.
  ///
  /// In zh, this message translates to:
  /// **'重试次数'**
  String get retryCount;

  /// No description provided for @retryCountDescription.
  ///
  /// In zh, this message translates to:
  /// **'同步失败时的重试次数'**
  String get retryCountDescription;

  /// No description provided for @retryDelay.
  ///
  /// In zh, this message translates to:
  /// **'重试间隔'**
  String get retryDelay;

  /// No description provided for @retryDelayDescription.
  ///
  /// In zh, this message translates to:
  /// **'重试之间的等待时间（秒）'**
  String get retryDelayDescription;

  /// No description provided for @realtimeDelay.
  ///
  /// In zh, this message translates to:
  /// **'实时同步延迟'**
  String get realtimeDelay;

  /// No description provided for @realtimeDelayDescription.
  ///
  /// In zh, this message translates to:
  /// **'实时同步的文件变更延迟（秒）'**
  String get realtimeDelayDescription;

  /// No description provided for @dataManagement.
  ///
  /// In zh, this message translates to:
  /// **'数据管理'**
  String get dataManagement;

  /// No description provided for @exportConfig.
  ///
  /// In zh, this message translates to:
  /// **'导出配置'**
  String get exportConfig;

  /// No description provided for @importConfig.
  ///
  /// In zh, this message translates to:
  /// **'导入配置'**
  String get importConfig;

  /// No description provided for @openSourceInfo.
  ///
  /// In zh, this message translates to:
  /// **'开源信息'**
  String get openSourceInfo;

  /// No description provided for @githubRepository.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 仓库'**
  String get githubRepository;

  /// No description provided for @authorHomepage.
  ///
  /// In zh, this message translates to:
  /// **'作者主页'**
  String get authorHomepage;

  /// No description provided for @dependencies.
  ///
  /// In zh, this message translates to:
  /// **'开源依赖'**
  String get dependencies;

  /// No description provided for @syncLogsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'同步日志'**
  String get syncLogsPageTitle;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @clearLogs.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clearLogs;

  /// No description provided for @searchLogs.
  ///
  /// In zh, this message translates to:
  /// **'搜索日志...'**
  String get searchLogs;

  /// No description provided for @noLogs.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogs;

  /// No description provided for @noLogsDescription.
  ///
  /// In zh, this message translates to:
  /// **'执行同步任务后日志将显示在这里'**
  String get noLogsDescription;

  /// No description provided for @deletedRepository.
  ///
  /// In zh, this message translates to:
  /// **'已删除的仓库'**
  String get deletedRepository;

  /// No description provided for @deleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get deleted;

  /// No description provided for @success.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get success;

  /// No description provided for @failed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get failed;

  /// No description provided for @inProgress.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get inProgress;

  /// No description provided for @successFailCount.
  ///
  /// In zh, this message translates to:
  /// **'成功: {success} 失败: {failed}'**
  String successFailCount(int success, int failed);

  /// No description provided for @sourceDevice.
  ///
  /// In zh, this message translates to:
  /// **'来源: {device} / {user}'**
  String sourceDevice(Object device, Object user);

  /// No description provided for @syncInRepositoryPage.
  ///
  /// In zh, this message translates to:
  /// **'仓库同步请在\\\"仓库\\\"页面执行'**
  String get syncInRepositoryPage;

  /// No description provided for @startTime.
  ///
  /// In zh, this message translates to:
  /// **'开始时间'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In zh, this message translates to:
  /// **'结束时间'**
  String get endTime;

  /// No description provided for @inProgress2.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get inProgress2;

  /// No description provided for @totalDuration.
  ///
  /// In zh, this message translates to:
  /// **'总耗时'**
  String get totalDuration;

  /// No description provided for @totalFiles.
  ///
  /// In zh, this message translates to:
  /// **'总文件数'**
  String get totalFiles;

  /// No description provided for @errorMessage.
  ///
  /// In zh, this message translates to:
  /// **'错误信息:'**
  String get errorMessage;

  /// No description provided for @confirmClearLogs.
  ///
  /// In zh, this message translates to:
  /// **'确认清空'**
  String get confirmClearLogs;

  /// No description provided for @clearLogsConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空所有同步日志吗？此操作不可恢复。'**
  String get clearLogsConfirm;

  /// No description provided for @versionControlPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'版本控制'**
  String get versionControlPageTitle;

  /// No description provided for @selectSyncTask.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一个同步任务'**
  String get selectSyncTask;

  /// No description provided for @initializeRepository.
  ///
  /// In zh, this message translates to:
  /// **'初始化版本库'**
  String get initializeRepository;

  /// No description provided for @uninitialized.
  ///
  /// In zh, this message translates to:
  /// **'未初始化'**
  String get uninitialized;

  /// No description provided for @changesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个更改'**
  String changesCount(int count);

  /// No description provided for @branches.
  ///
  /// In zh, this message translates to:
  /// **'分支'**
  String get branches;

  /// No description provided for @stash.
  ///
  /// In zh, this message translates to:
  /// **'Stash'**
  String get stash;

  /// No description provided for @conflicts.
  ///
  /// In zh, this message translates to:
  /// **'冲突({count})'**
  String conflicts(int count);

  /// No description provided for @fileDiff.
  ///
  /// In zh, this message translates to:
  /// **'文件差异: {path}'**
  String fileDiff(Object path);

  /// No description provided for @initialCommitNoDiff.
  ///
  /// In zh, this message translates to:
  /// **'初始提交暂不支持父提交对比'**
  String get initialCommitNoDiff;

  /// No description provided for @commitDiff.
  ///
  /// In zh, this message translates to:
  /// **'提交差异: {id}'**
  String commitDiff(Object id);

  /// No description provided for @noChangeDetected.
  ///
  /// In zh, this message translates to:
  /// **'该提交未检测到可展示差异'**
  String get noChangeDetected;

  /// No description provided for @workingDiff.
  ///
  /// In zh, this message translates to:
  /// **'工作区差异: {path}'**
  String workingDiff(Object path);

  /// No description provided for @noWorkingDiff.
  ///
  /// In zh, this message translates to:
  /// **'该文件当前没有可展示差异'**
  String get noWorkingDiff;

  /// No description provided for @stageDiffNotAvailable.
  ///
  /// In zh, this message translates to:
  /// **'该文件暂无可展示的差异，请先暂存后重试'**
  String get stageDiffNotAvailable;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @aboutPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutPageTitle;

  /// No description provided for @mainFeatures.
  ///
  /// In zh, this message translates to:
  /// **'主要功能'**
  String get mainFeatures;

  /// No description provided for @mitLicense.
  ///
  /// In zh, this message translates to:
  /// **'MIT 许可证'**
  String get mitLicense;

  /// No description provided for @mitLicenseInfo.
  ///
  /// In zh, this message translates to:
  /// **'本软件遵循MIT开源协议'**
  String get mitLicenseInfo;

  /// No description provided for @feature1.
  ///
  /// In zh, this message translates to:
  /// **'本地文件夹与SMB/WebDAV远端同步'**
  String get feature1;

  /// No description provided for @feature2.
  ///
  /// In zh, this message translates to:
  /// **'默认双向同步，支持一键切换仅本地模式'**
  String get feature2;

  /// No description provided for @feature3.
  ///
  /// In zh, this message translates to:
  /// **'文件版本管理与恢复'**
  String get feature3;

  /// No description provided for @feature4.
  ///
  /// In zh, this message translates to:
  /// **'定时同步与实时文件监听'**
  String get feature4;

  /// No description provided for @feature5.
  ///
  /// In zh, this message translates to:
  /// **'冲突检测与智能处理'**
  String get feature5;

  /// No description provided for @feature6.
  ///
  /// In zh, this message translates to:
  /// **'系统托盘集成，后台静默运行'**
  String get feature6;

  /// No description provided for @automationPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动化配置'**
  String get automationPageTitle;

  /// No description provided for @automationRules.
  ///
  /// In zh, this message translates to:
  /// **'自动化规则'**
  String get automationRules;

  /// No description provided for @newRule.
  ///
  /// In zh, this message translates to:
  /// **'新建规则'**
  String get newRule;

  /// No description provided for @ruleEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get ruleEnabled;

  /// No description provided for @ruleDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get ruleDisabled;

  /// No description provided for @triggerType.
  ///
  /// In zh, this message translates to:
  /// **'触发方式'**
  String get triggerType;

  /// No description provided for @timeBased.
  ///
  /// In zh, this message translates to:
  /// **'定时'**
  String get timeBased;

  /// No description provided for @changeBased.
  ///
  /// In zh, this message translates to:
  /// **'修改时触发'**
  String get changeBased;

  /// No description provided for @actionType.
  ///
  /// In zh, this message translates to:
  /// **'操作类型'**
  String get actionType;

  /// No description provided for @intervalMinutes.
  ///
  /// In zh, this message translates to:
  /// **'间隔时间(分钟)'**
  String get intervalMinutes;

  /// No description provided for @debounceSeconds.
  ///
  /// In zh, this message translates to:
  /// **'防抖延迟(秒)'**
  String get debounceSeconds;

  /// No description provided for @autoCommitOnInterval.
  ///
  /// In zh, this message translates to:
  /// **'自动提交'**
  String get autoCommitOnInterval;

  /// No description provided for @autoPushOnInterval.
  ///
  /// In zh, this message translates to:
  /// **'自动推送'**
  String get autoPushOnInterval;

  /// No description provided for @commitOnChange.
  ///
  /// In zh, this message translates to:
  /// **'修改时自动提交'**
  String get commitOnChange;

  /// No description provided for @pushAfterCommit.
  ///
  /// In zh, this message translates to:
  /// **'提交后推送'**
  String get pushAfterCommit;

  /// No description provided for @commitMessageTemplate.
  ///
  /// In zh, this message translates to:
  /// **'提交信息模板'**
  String get commitMessageTemplate;

  /// No description provided for @templateVariables.
  ///
  /// In zh, this message translates to:
  /// **'可用变量: repo_name(仓库名) file_count(文件数) additions/deletions(增删行数) timestamp(时间戳) date(日期)'**
  String get templateVariables;

  /// No description provided for @lastTriggered.
  ///
  /// In zh, this message translates to:
  /// **'最后触发'**
  String get lastTriggered;

  /// No description provided for @noAutomationRules.
  ///
  /// In zh, this message translates to:
  /// **'暂无自动化规则'**
  String get noAutomationRules;

  /// No description provided for @createFirstRule.
  ///
  /// In zh, this message translates to:
  /// **'创建第一个规则'**
  String get createFirstRule;

  /// No description provided for @editRule.
  ///
  /// In zh, this message translates to:
  /// **'编辑规则'**
  String get editRule;

  /// No description provided for @deleteRule.
  ///
  /// In zh, this message translates to:
  /// **'删除规则'**
  String get deleteRule;

  /// No description provided for @deleteRuleConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除规则\"{name}\"吗？'**
  String deleteRuleConfirm(Object name);

  /// No description provided for @selectRepository.
  ///
  /// In zh, this message translates to:
  /// **'选择仓库:'**
  String get selectRepository;

  /// No description provided for @noNoRepositories.
  ///
  /// In zh, this message translates to:
  /// **'暂无版本库'**
  String get noNoRepositories;

  /// No description provided for @noRepositoriesHint.
  ///
  /// In zh, this message translates to:
  /// **'请先在\\\"仓库\\\"页面注册仓库'**
  String get noRepositoriesHint;

  /// No description provided for @noRegisteredRepositories.
  ///
  /// In zh, this message translates to:
  /// **'暂无已注册仓库'**
  String get noRegisteredRepositories;

  /// No description provided for @goToRepositoriesPage.
  ///
  /// In zh, this message translates to:
  /// **'前往仓库页面'**
  String get goToRepositoriesPage;

  /// No description provided for @timeTrigger.
  ///
  /// In zh, this message translates to:
  /// **'定时触发'**
  String get timeTrigger;

  /// No description provided for @changeTrigger.
  ///
  /// In zh, this message translates to:
  /// **'修改时触发'**
  String get changeTrigger;

  /// No description provided for @commitMessageTemplateTitle.
  ///
  /// In zh, this message translates to:
  /// **'提交信息模板'**
  String get commitMessageTemplateTitle;

  /// No description provided for @availableVariables.
  ///
  /// In zh, this message translates to:
  /// **'可用变量 (点击插入):'**
  String get availableVariables;

  /// No description provided for @preview.
  ///
  /// In zh, this message translates to:
  /// **'预览效果:'**
  String get preview;

  /// No description provided for @commonTemplates.
  ///
  /// In zh, this message translates to:
  /// **'常用模板:'**
  String get commonTemplates;

  /// No description provided for @simpleCommit.
  ///
  /// In zh, this message translates to:
  /// **'简单提交'**
  String get simpleCommit;

  /// No description provided for @detailedCommit.
  ///
  /// In zh, this message translates to:
  /// **'详细提交'**
  String get detailedCommit;

  /// No description provided for @timestampedCommit.
  ///
  /// In zh, this message translates to:
  /// **'带时间戳'**
  String get timestampedCommit;

  /// No description provided for @semanticCommit.
  ///
  /// In zh, this message translates to:
  /// **'语义化'**
  String get semanticCommit;

  /// No description provided for @varRepoName.
  ///
  /// In zh, this message translates to:
  /// **'仓库名称'**
  String get varRepoName;

  /// No description provided for @varFileCount.
  ///
  /// In zh, this message translates to:
  /// **'变更文件数量'**
  String get varFileCount;

  /// No description provided for @varAdditions.
  ///
  /// In zh, this message translates to:
  /// **'新增行数'**
  String get varAdditions;

  /// No description provided for @varDeletions.
  ///
  /// In zh, this message translates to:
  /// **'删除行数'**
  String get varDeletions;

  /// No description provided for @varTimestamp.
  ///
  /// In zh, this message translates to:
  /// **'Unix时间戳'**
  String get varTimestamp;

  /// No description provided for @varDate.
  ///
  /// In zh, this message translates to:
  /// **'日期 (YYYY-MM-DD)'**
  String get varDate;

  /// No description provided for @varTime.
  ///
  /// In zh, this message translates to:
  /// **'时间 (HH:MM:SS)'**
  String get varTime;

  /// No description provided for @varBranch.
  ///
  /// In zh, this message translates to:
  /// **'当前分支名'**
  String get varBranch;

  /// No description provided for @varChangesSummary.
  ///
  /// In zh, this message translates to:
  /// **'变更文件摘要'**
  String get varChangesSummary;

  /// No description provided for @goToVersionControl.
  ///
  /// In zh, this message translates to:
  /// **'跳转到版本控制'**
  String get goToVersionControl;

  /// No description provided for @goToAutomation.
  ///
  /// In zh, this message translates to:
  /// **'跳转到自动化配置'**
  String get goToAutomation;

  /// No description provided for @fileManagement.
  ///
  /// In zh, this message translates to:
  /// **'文件管理'**
  String get fileManagement;

  /// No description provided for @rootDirectory.
  ///
  /// In zh, this message translates to:
  /// **'根目录'**
  String get rootDirectory;

  /// No description provided for @emptyDirectory.
  ///
  /// In zh, this message translates to:
  /// **'目录为空'**
  String get emptyDirectory;

  /// No description provided for @ignored.
  ///
  /// In zh, this message translates to:
  /// **'已忽略'**
  String get ignored;

  /// No description provided for @tracked.
  ///
  /// In zh, this message translates to:
  /// **'已跟踪'**
  String get tracked;

  /// No description provided for @ignoreThisItem.
  ///
  /// In zh, this message translates to:
  /// **'忽略此项'**
  String get ignoreThisItem;

  /// No description provided for @unignoreItem.
  ///
  /// In zh, this message translates to:
  /// **'取消忽略'**
  String get unignoreItem;

  /// No description provided for @enterDirectory.
  ///
  /// In zh, this message translates to:
  /// **'进入目录'**
  String get enterDirectory;

  /// No description provided for @addIgnoreRule.
  ///
  /// In zh, this message translates to:
  /// **'添加忽略规则'**
  String get addIgnoreRule;

  /// No description provided for @viewAllRules.
  ///
  /// In zh, this message translates to:
  /// **'查看所有规则'**
  String get viewAllRules;

  /// No description provided for @ignoreRuleList.
  ///
  /// In zh, this message translates to:
  /// **'忽略规则列表'**
  String get ignoreRuleList;

  /// No description provided for @defaultRulesNotDeletable.
  ///
  /// In zh, this message translates to:
  /// **'默认规则 (不可删除)'**
  String get defaultRulesNotDeletable;

  /// No description provided for @customRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get customRules;

  /// No description provided for @noCustomRules.
  ///
  /// In zh, this message translates to:
  /// **'暂无自定义规则'**
  String get noCustomRules;

  /// No description provided for @ruleCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则'**
  String ruleCount(int count);

  /// No description provided for @enterIgnorePattern.
  ///
  /// In zh, this message translates to:
  /// **'输入忽略模式（支持通配符 * 和 ?）:'**
  String get enterIgnorePattern;

  /// No description provided for @patternExample.
  ///
  /// In zh, this message translates to:
  /// **'例如: *.log, temp/, build/'**
  String get patternExample;

  /// No description provided for @directoryRuleHint.
  ///
  /// In zh, this message translates to:
  /// **'提示：以 / 结尾表示目录'**
  String get directoryRuleHint;

  /// No description provided for @selectRepositoryFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一个仓库'**
  String get selectRepositoryFirst;

  /// No description provided for @deleteRepository.
  ///
  /// In zh, this message translates to:
  /// **'删除仓库'**
  String get deleteRepository;

  /// No description provided for @migrateRepository.
  ///
  /// In zh, this message translates to:
  /// **'迁移仓库'**
  String get migrateRepository;

  /// No description provided for @deleteRepositoryConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除仓库\"{name}\"吗？'**
  String deleteRepositoryConfirm(Object name);

  /// No description provided for @deleteRepositoryHint.
  ///
  /// In zh, this message translates to:
  /// **'只会从应用中移除仓库注册，不会删除本地文件。'**
  String get deleteRepositoryHint;

  /// No description provided for @notice.
  ///
  /// In zh, this message translates to:
  /// **'注意'**
  String get notice;

  /// No description provided for @currentPath.
  ///
  /// In zh, this message translates to:
  /// **'当前路径'**
  String get currentPath;

  /// No description provided for @newPath.
  ///
  /// In zh, this message translates to:
  /// **'新路径'**
  String get newPath;

  /// No description provided for @migrate.
  ///
  /// In zh, this message translates to:
  /// **'迁移'**
  String get migrate;

  /// No description provided for @samePathError.
  ///
  /// In zh, this message translates to:
  /// **'新路径与当前路径相同'**
  String get samePathError;

  /// No description provided for @migrateFailed.
  ///
  /// In zh, this message translates to:
  /// **'迁移失败'**
  String get migrateFailed;

  /// No description provided for @deleteNanosyncFolder.
  ///
  /// In zh, this message translates to:
  /// **'同时删除 .nanosync 版本控制文件夹'**
  String get deleteNanosyncFolder;

  /// No description provided for @deleteNanosyncFolderHint.
  ///
  /// In zh, this message translates to:
  /// **'将永久删除仓库的所有版本历史记录，此操作不可恢复！'**
  String get deleteNanosyncFolderHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
