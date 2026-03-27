import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/utils/device_identity.dart';
import '../../core/theme/app_theme.dart';
import '../providers/vc_repository_provider.dart';
import '../../features/repository/repository_list_page.dart';
import '../../features/remote/remote_connections_page.dart';
import '../../features/version_control/vc_page.dart';
import '../../features/automation/automation_page.dart';
import '../../features/sync_log/log_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/about/about_page.dart';
import '../../l10n/l10n.dart';

/// 页面索引常量
class AppPageIndex {
  static const int repositories = 0;
  static const int remoteConnections = 1;
  static const int versionControl = 2;
  static const int automation = 3;
  static const int syncLogs = 4;
  static const int settings = 5;
  static const int about = 6;
}

/// InheritedWidget 用于在子组件中访问 AppShell 状态
class _AppShellScope extends InheritedWidget {
  final _AppShellState shellState;

  const _AppShellScope({required this.shellState, required super.child});

  static _AppShellState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppShellScope>();
    assert(scope != null, 'AppShellScope not found in context');
    return scope!.shellState;
  }

  @override
  bool updateShouldNotify(_AppShellScope oldWidget) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();

  /// 导航到指定页面，可选择性地选择一个仓库
  static void navigateToPage(
    BuildContext context, {
    required int pageIndex,
    String? repositoryId,
  }) {
    final shellState = _AppShellScope.of(context);
    shellState.navigateToPage(pageIndex, repositoryId: repositoryId);
  }
}

class _AppShellState extends State<AppShell> with WindowListener {
  int _selectedIndex = 0;
  bool _isMaximized = false;
  late final DeviceIdentity _deviceIdentity;

  @override
  void initState() {
    super.initState();
    _deviceIdentity = DeviceIdentityResolver.resolve();
    windowManager.addListener(this);
    _checkMaximized();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initVersionControl();
    });
  }

  Future<void> _initVersionControl() async {
    final vcProvider = context.read<VcRepositoryProvider>();
    await vcProvider.loadRepositories();
    if (!mounted) return;

    if (vcProvider.currentRepository == null &&
        vcProvider.repositories.isNotEmpty) {
      await vcProvider.selectRepository(vcProvider.repositories.first.id);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  Future<void> _updateWindowEffect(bool isDark, bool useMica) async {
    if (useMica) {
      await Window.setEffect(
        effect: WindowEffect.mica,
        color: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
        dark: isDark,
      );
    } else {
      await Window.setEffect(
        effect: WindowEffect.solid,
        color: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
        dark: isDark,
      );
    }
  }

  /// 设置标题栏样式（隐藏系统按钮），出错时静默忽略
  void _applyTitleBarStyle() {
    windowManager
        .setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false)
        .catchError((_) {});
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
      _applyTitleBarStyle();
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
      _applyTitleBarStyle();
    }
  }

  /// 导航到指定页面，可选择性地选择一个仓库
  void navigateToPage(int pageIndex, {String? repositoryId}) {
    if (repositoryId != null) {
      final vcProvider = context.read<VcRepositoryProvider>();
      vcProvider.selectRepository(repositoryId);
    }
    setState(() => _selectedIndex = pageIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>();
    final vcProvider = context.watch<VcRepositoryProvider>();
    final isDark =
        theme.themeMode == ThemeMode.dark ||
        (theme.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    final l10n = context.l10n;

    final pages = [
      const RepositoryListPage(),
      const RemoteConnectionsPage(),
      VersionControlPage(repositoryId: vcProvider.currentRepository?.id),
      const AutomationPage(),
      const LogPage(),
      const SettingsPage(),
      const AboutPage(),
    ];

    _updateWindowEffect(isDark, theme.useMica);

    return DefaultTextStyle(
      style: AppStyles.textStyleBody,
      child: _AppShellScope(
        shellState: this,
        child: NavigationView(
          titleBar: _buildTitleBar(isDark),
          paneBodyBuilder: (item, child) {
            return Container(
              color: theme.useMica ? Colors.transparent : null,
              child: pages[_selectedIndex],
            );
          },
          pane: NavigationPane(
            selected: _selectedIndex,
            onChanged: (index) => setState(() => _selectedIndex = index),
            displayMode: PaneDisplayMode.expanded,
            size: const NavigationPaneSize(openWidth: 240),
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.view),
                title: Text(
                  l10n.navRepositories,
                  style: AppStyles.textStyleBody,
                ),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.server),
                title: Text(
                  l10n.navRemoteConnections,
                  style: AppStyles.textStyleBody,
                ),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.git_graph),
                title: Text(
                  l10n.navVersionControl,
                  style: AppStyles.textStyleBody,
                ),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.settings),
                title: Text(
                  l10n.automationPageTitle,
                  style: AppStyles.textStyleBody,
                ),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.list),
                title: Text(l10n.navSyncLogs, style: AppStyles.textStyleBody),
                body: const SizedBox.shrink(),
              ),
            ],
            footerItems: [
              PaneItem(
                icon: const Icon(FluentIcons.settings),
                title: Text(l10n.navSettings, style: AppStyles.textStyleBody),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.info),
                title: Text(l10n.navAbout, style: AppStyles.textStyleBody),
                body: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTitleBar(bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          height: 40,
          color: Colors.transparent,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppStyles.primaryColor,
                      AppStyles.primaryColor.withBlue(200),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  FluentIcons.sync_folder,
                  size: 10,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'NanoSync',
                style: AppStyles.textStyleBody.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              _buildSyncStatus(isDark),
              const SizedBox(width: 8),
              _buildWindowControls(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatus(bool isDark) {
    final fp = _deviceIdentity.fingerprint;
    final shortFp = fp.length > 8 ? fp.substring(fp.length - 8) : fp;
    final l10n = context.l10n;
    final deviceName = _deviceIdentity.deviceName.isEmpty
        ? l10n.unknownDevice
        : _deviceIdentity.deviceName;
    final username = _deviceIdentity.username.isEmpty
        ? l10n.unknownUser
        : _deviceIdentity.username;

    return Tooltip(
      message: l10n.titleBarDeviceTooltip(
        l10n.deviceLabel,
        deviceName,
        l10n.userLabel,
        username,
        l10n.fingerprintLabel,
        _deviceIdentity.fingerprint,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.server,
              size: 12,
              color: isDark ? Colors.grey[20] : Colors.grey[130],
            ),
            const SizedBox(width: 6),
            Text(
              l10n.titleBarDeviceBadge(deviceName, username, shortFp),
              style: AppStyles.textStyleCaption.copyWith(
                fontSize: 11,
                color: isDark ? Colors.grey[20] : Colors.grey[130],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowControls(bool isDark) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _WindowButton(
            icon: FluentIcons.chrome_minimize,
            onPressed: () => windowManager.minimize(),
            isDark: isDark,
          ),
          _WindowButton(
            icon: _isMaximized ? FluentIcons.back_to_window : FluentIcons.stop,
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            isDark: isDark,
          ),
          _WindowButton(
            icon: FluentIcons.chrome_close,
            onPressed: () => windowManager.close(),
            isDark: isDark,
            isClose: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          color: _getBackgroundColor(),
          child: Icon(widget.icon, size: 12, color: _getIconColor()),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    if (!_isHovering) return Colors.transparent;
    if (widget.isClose) return AppStyles.errorColor;
    return widget.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
  }

  Color _getIconColor() {
    if (widget.isClose && _isHovering) return Colors.white;
    return widget.isDark ? Colors.white : Colors.black;
  }
}
