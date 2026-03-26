import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_theme.dart';
import '../providers/task_provider.dart';
import '../../features/task_management/task_list_page.dart';
import '../../features/realtime_monitor/monitor_page.dart';
import '../../features/version_management/version_page.dart';
import '../../features/sync_log/log_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/about/about_page.dart';

/// 应用主Shell - 自定义Windows 11风格标题栏 + Mica材质
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  int _selectedIndex = 0;
  bool _isMaximized = false;

  final List<Widget> _pages = const [
    TaskListPage(),
    MonitorPage(),
    VersionPage(),
    LogPage(),
    SettingsPage(),
    AboutPage(),
  ];

  final List<NavigationPaneItem> _items = [
    PaneItem(
      icon: const Icon(FluentIcons.task_list),
      title: const Text('同步任务'),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      icon: const Icon(FluentIcons.view),
      title: const Text('实时监控'),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      icon: const Icon(FluentIcons.history),
      title: const Text('版本管理'),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      icon: const Icon(FluentIcons.list),
      title: const Text('同步日志'),
      body: const SizedBox.shrink(),
    ),
  ];

  final List<NavigationPaneItem> _footerItems = [
    PaneItem(
      icon: const Icon(FluentIcons.settings),
      title: const Text('系统设置'),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      icon: const Icon(FluentIcons.info),
      title: const Text('关于'),
      body: const SizedBox.shrink(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
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

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final isDark =
        theme.themeMode == ThemeMode.dark ||
        (theme.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return NavigationView(
      titleBar: _buildCustomTitleBar(isDark),
      paneBodyBuilder: (item, child) {
        return Acrylic(
          blurAmount: 30,
          tintAlpha: isDark ? 0.5 : 0.7,
          luminosityAlpha: isDark ? 0.15 : 0.05,
          child: _pages[_selectedIndex],
        );
      },
      pane: NavigationPane(
        selected: _selectedIndex,
        onChanged: (index) => setState(() => _selectedIndex = index),
        displayMode: PaneDisplayMode.expanded,
        items: _items,
        footerItems: _footerItems,
        size: const NavigationPaneSize(openWidth: 240),
      ),
    );
  }

  PreferredSizeWidget _buildCustomTitleBar(bool isDark) {
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
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  FluentIcons.sync_folder,
                  size: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'NanoSync',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              _buildNetworkStatus(isDark),
              const SizedBox(width: 12),
              _buildSyncStatus(isDark),
              const SizedBox(width: 8),
              _buildWindowControls(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatus(bool isDark) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '在线',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey[80] : Colors.grey[100],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStatus(bool isDark) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        if (provider.hasRunningTask) {
          return Row(
            children: [
              const SizedBox(width: 12, height: 12, child: ProgressRing()),
              const SizedBox(width: 6),
              Text(
                '同步中',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[80] : Colors.grey[100],
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
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
            icon: _isMaximized
                ? FluentIcons.double_chevron_down
                : FluentIcons.checkbox,
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
    if (widget.isClose) return Colors.red;
    return widget.isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);
  }

  Color _getIconColor() {
    if (widget.isClose && _isHovering) return Colors.white;
    return widget.isDark ? Colors.white : Colors.black;
  }
}
