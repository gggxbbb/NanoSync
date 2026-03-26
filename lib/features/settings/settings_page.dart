import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

/// 设置页面
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
    final theme = context.watch<AppTheme>();

    return ScaffoldPage(
      header: const PageHeader(title: Text('系统设置')),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('外观设置', [
              _buildThemeSelector(theme),
              const SizedBox(height: 12),
              ToggleSwitch(
                checked: theme.useMica,
                onChanged: (v) => theme.setUseMica(v),
                content: const Text('启用云母/亚克力特效'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSection('系统设置', [
              ToggleSwitch(
                checked: _autoStart,
                onChanged: (v) => setState(() => _autoStart = v),
                content: const Text('开机自启'),
              ),
              const SizedBox(height: 12),
              ToggleSwitch(
                checked: _minimizeToTray,
                onChanged: (v) => setState(() => _minimizeToTray = v),
                content: const Text('最小化到系统托盘'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildSection('版本管理', [
              _buildIntSetting('保留最近版本数', _maxVersions,
                  (v) => setState(() => _maxVersions = v)),
              _buildIntSetting('保留天数', _maxVersionDays,
                  (v) => setState(() => _maxVersionDays = v)),
              _buildIntSetting('总容量限制(GB)', _maxVersionSizeGB,
                  (v) => setState(() => _maxVersionSizeGB = v)),
            ]),
            const SizedBox(height: 24),
            _buildSection('同步设置', [
              _buildIntSetting(
                  '重试次数', _retryCount, (v) => setState(() => _retryCount = v)),
              _buildIntSetting('重试间隔(秒)', _retryDelay,
                  (v) => setState(() => _retryDelay = v)),
              _buildIntSetting('实时同步延迟(秒)', _realtimeDelay,
                  (v) => setState(() => _realtimeDelay = v)),
            ]),
            const SizedBox(height: 24),
            _buildSection('数据管理', [
              Row(
                children: [
                  OutlinedButton(
                    child: const Text('导出配置'),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    child: const Text('导入配置'),
                    onPressed: () {},
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 24),
            _buildAboutSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeSelector(AppTheme theme) {
    return Row(
      children: [
        const Text('主题模式:'),
        const SizedBox(width: 16),
        ...['system', 'light', 'dark'].map((mode) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ToggleButton(
              checked: theme.themeMode.name == mode,
              onChanged: (v) {
                if (v) {
                  theme.setThemeMode(ThemeMode.values.byName(mode));
                }
              },
              child: Text(mode == 'system'
                  ? '跟随系统'
                  : mode == 'light'
                      ? '浅色'
                      : '深色'),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildIntSetting(
      String label, int value, void Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 180, child: Text(label)),
          SizedBox(
            width: 100,
            child: NumberBox(
              value: value,
              onChanged: (v) => onChanged(v ?? value),
              min: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('关于与开源信息',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLinkRow(FluentIcons.open_source, 'GitHub 仓库',
                    'github.com/gggxbbb/NanoSync',
                    url: 'https://github.com/gggxbbb/NanoSync'),
                _buildLinkRow(FluentIcons.contact, 'GitHub 主页', '@gggxbbb',
                    url: 'https://github.com/gggxbbb'),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text('开源依赖协议',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._dependencyLicenses.map((d) => _buildLicenseRow(d)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'NanoSync ${AppConstants.appVersion}  ·  MIT License',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLinkRow(IconData icon, String label, String display,
      {required String url}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _launchUrl(url),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 12),
              SizedBox(width: 100, child: Text(label)),
              Expanded(
                child: Text(
                  display,
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Icon(FluentIcons.navigate_external_inline, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLicenseRow(_DependencyInfo dep) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(dep.name, style: const TextStyle(fontSize: 13)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(dep.license,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static const List<_DependencyInfo> _dependencyLicenses = [
    _DependencyInfo('fluent_ui', 'BSD-3'),
    _DependencyInfo('provider', 'MIT'),
    _DependencyInfo('sqflite_common_ffi', 'BSD-3'),
    _DependencyInfo('webdav_client_plus', 'BSD-3'),
    _DependencyInfo('file_picker', 'MIT'),
    _DependencyInfo('path_provider', 'BSD-3'),
    _DependencyInfo('watcher', 'BSD-3'),
    _DependencyInfo('shared_preferences', 'BSD-3'),
    _DependencyInfo('crypto', 'BSD-3'),
    _DependencyInfo('archive', 'MIT'),
    _DependencyInfo('intl', 'BSD-3'),
    _DependencyInfo('system_tray', 'MIT'),
    _DependencyInfo('win32', 'BSD-3'),
    _DependencyInfo('uuid', 'MIT'),
    _DependencyInfo('rxdart', 'Apache-2.0'),
    _DependencyInfo('dio', 'MIT'),
    _DependencyInfo('url_launcher', 'BSD-3'),
    _DependencyInfo('system_theme', 'MIT'),
    _DependencyInfo('fluentui_system_icons', 'MIT'),
  ];
}

class _DependencyInfo {
  final String name;
  final String license;
  const _DependencyInfo(this.name, this.license);
}
