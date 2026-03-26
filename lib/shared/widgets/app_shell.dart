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
    final theme = context.watch<ThemeManager>();
    final isDark =
        theme.themeMode == ThemeMode.dark ||
        (theme.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    _updateWindowEffect(isDark, theme.useMica);

    return DefaultTextStyle(
      style: AppStyles.textStyleBody,
      child: NavigationView(
        titleBar: _buildTitleBar(isDark),
        paneBodyBuilder: (item, child) {
          return Container(
            color: theme.useMica ? Colors.transparent : null,
            child: _pages[_selectedIndex],
          );
        },
        pane: NavigationPane(
          selected: _selectedIndex,
          onChanged: (index) => setState(() => _selectedIndex = index),
          displayMode: PaneDisplayMode.expanded,
          size: const NavigationPaneSize(openWidth: 240),
          items: [
            PaneItem(
              icon: const Icon(FluentIcons.sync_folder),
              title: Text('同步任务', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
            PaneItem(
              icon: const Icon(FluentIcons.view),
              title: Text('实时监控', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
            PaneItem(
              icon: const Icon(FluentIcons.history),
              title: Text('版本管理', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
            PaneItem(
              icon: const Icon(FluentIcons.list),
              title: Text('同步日志', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
          ],
          footerItems: [
            PaneItem(
              icon: const Icon(FluentIcons.settings),
              title: Text('系统设置', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
            PaneItem(
              icon: const Icon(FluentIcons.info),
              title: Text('关于', style: AppStyles.textStyleBody),
              body: const SizedBox.shrink(),
            ),
          ],
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
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        if (provider.hasRunningTask) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppStyles.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: ProgressRing(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  '同步中',
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.primaryColor,
                  ),
                ),
              ],
            ),
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
