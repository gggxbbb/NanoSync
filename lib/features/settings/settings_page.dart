import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/inputs.dart';
import '../../l10n/l10n.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoStart = false;
  bool _minimizeToTray = true;
  int _maxVersions = AppConstants.defaultMaxVersions;
  int _maxVersionDays = AppConstants.defaultMaxVersionDays;
  int _maxVersionSizeGB = AppConstants.defaultMaxVersionSizeGB;
  int _retryCount = AppConstants.defaultRetryCount;
  int _retryDelay = AppConstants.defaultRetryDelaySeconds;
  int _realtimeDelay = AppConstants.defaultRealtimeDelaySeconds;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>();
    final isDark =
        theme.themeMode == ThemeMode.dark ||
        (theme.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          context.l10n.settingsPageTitle,
          style: AppStyles.textStyleTitle.copyWith(color: primaryTextColor),
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsCard(
              title: '外观',
              icon: FluentIcons.color,
              child: Column(
                children: [
                  SettingRow(
                    label: '主题模式',
                    description: '选择应用的主题外观',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ThemeModeButton(
                          mode: ThemeMode.system,
                          currentMode: theme.themeMode,
                          label: '跟随系统',
                          onChanged: theme.setThemeMode,
                        ),
                        const SizedBox(width: 8),
                        _ThemeModeButton(
                          mode: ThemeMode.light,
                          currentMode: theme.themeMode,
                          label: '浅色',
                          onChanged: theme.setThemeMode,
                        ),
                        const SizedBox(width: 8),
                        _ThemeModeButton(
                          mode: ThemeMode.dark,
                          currentMode: theme.themeMode,
                          label: '深色',
                          onChanged: theme.setThemeMode,
                        ),
                      ],
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '云母特效',
                    description: '启用Windows 11风格的云母/亚克力背景效果',
                    trailing: ToggleSwitch(
                      checked: theme.useMica,
                      onChanged: (v) => theme.setUseMica(v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsCard(
              title: '系统',
              icon: FluentIcons.settings,
              child: Column(
                children: [
                  SettingRow(
                    label: '开机自启',
                    description: 'Windows启动时自动运行应用',
                    trailing: ToggleSwitch(
                      checked: _autoStart,
                      onChanged: (v) => setState(() => _autoStart = v),
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '最小化到托盘',
                    description: '关闭窗口时最小化到系统托盘而非退出',
                    trailing: ToggleSwitch(
                      checked: _minimizeToTray,
                      onChanged: (v) => setState(() => _minimizeToTray = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsCard(
              title: '版本管理',
              icon: FluentIcons.history,
              child: Column(
                children: [
                  SettingRow(
                    label: '保留版本数',
                    description: '每个文件保留的最大版本数量',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _maxVersions,
                        onChanged: (v) =>
                            setState(() => _maxVersions = v ?? _maxVersions),
                        min: 1,
                        max: 100,
                      ),
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '保留天数',
                    description: '版本文件的保留天数',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _maxVersionDays,
                        onChanged: (v) => setState(
                          () => _maxVersionDays = v ?? _maxVersionDays,
                        ),
                        min: 1,
                        max: 365,
                      ),
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '容量限制',
                    description: '版本存储的最大容量（GB）',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _maxVersionSizeGB,
                        onChanged: (v) => setState(
                          () => _maxVersionSizeGB = v ?? _maxVersionSizeGB,
                        ),
                        min: 1,
                        max: 1000,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsCard(
              title: '同步设置',
              icon: FluentIcons.sync,
              child: Column(
                children: [
                  SettingRow(
                    label: '重试次数',
                    description: '同步失败时的重试次数',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _retryCount,
                        onChanged: (v) =>
                            setState(() => _retryCount = v ?? _retryCount),
                        min: 0,
                        max: 10,
                      ),
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '重试间隔',
                    description: '重试之间的等待时间（秒）',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _retryDelay,
                        onChanged: (v) =>
                            setState(() => _retryDelay = v ?? _retryDelay),
                        min: 1,
                        max: 60,
                      ),
                    ),
                  ),
                  const SettingDivider(),
                  SettingRow(
                    label: '实时同步延迟',
                    description: '实时同步的文件变更延迟（秒）',
                    trailing: SizedBox(
                      width: 100,
                      child: NumberBox(
                        value: _realtimeDelay,
                        onChanged: (v) => setState(
                          () => _realtimeDelay = v ?? _realtimeDelay,
                        ),
                        min: 1,
                        max: 60,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsCard(
              title: '数据管理',
              icon: FluentIcons.database,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    OutlinedButton(child: const Text('导出配置'), onPressed: () {}),
                    const SizedBox(width: 12),
                    OutlinedButton(child: const Text('导入配置'), onPressed: () {}),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildAboutSection(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection(bool isDark) {
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return SettingsCard(
      title: '开源信息',
      icon: FluentIcons.open_source,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLinkRow(
            isDark,
            FluentIcons.open_source,
            'GitHub 仓库',
            'github.com/gggxbbb/NanoSync',
            url: 'https://github.com/gggxbbb/NanoSync',
          ),
          const SizedBox(height: 8),
          _buildLinkRow(
            isDark,
            FluentIcons.contact,
            '作者主页',
            '@gggxbbb',
            url: 'https://github.com/gggxbbb',
          ),
          const SizedBox(height: 16),
          Text(
            '开源依赖',
            style: AppStyles.textStyleBody.copyWith(
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _dependencyLicenses
                .map(
                  (d) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey[20],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${d.name} (${d.license})',
                      style: AppStyles.textStyleCaption.copyWith(
                        fontSize: 11,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'NanoSync ${AppConstants.appVersion} · MIT License',
              style: AppStyles.textStyleCaption.copyWith(
                fontSize: 12,
                color: isDark ? Colors.grey[120] : Colors.grey[140],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
    bool isDark,
    IconData icon,
    String label,
    String display, {
    required String url,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launchUrl(url),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppStyles.primaryColor),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: AppStyles.textStyleBody.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            Expanded(
              child: Text(
                display,
                style: AppStyles.textStyleBody.copyWith(
                  color: AppStyles.primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Icon(
              FluentIcons.navigate_external_inline,
              size: 14,
              color: AppStyles.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static const _dependencyLicenses = [
    _DependencyInfo('fluent_ui', 'BSD-3'),
    _DependencyInfo('provider', 'MIT'),
    _DependencyInfo('sqflite', 'BSD-3'),
    _DependencyInfo('webdav_client_plus', 'BSD-3'),
    _DependencyInfo('file_picker', 'MIT'),
    _DependencyInfo('window_manager', 'MIT'),
    _DependencyInfo('flutter_acrylic', 'MIT'),
    _DependencyInfo('system_tray', 'MIT'),
  ];
}

class _ThemeModeButton extends StatelessWidget {
  final ThemeMode mode;
  final ThemeMode currentMode;
  final String label;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeModeButton({
    required this.mode,
    required this.currentMode,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == currentMode;
    return ToggleButton(
      checked: isSelected,
      onChanged: (v) {
        if (v) onChanged(mode);
      },
      child: Text(label),
    );
  }
}

class _DependencyInfo {
  final String name;
  final String license;
  const _DependencyInfo(this.name, this.license);
}
