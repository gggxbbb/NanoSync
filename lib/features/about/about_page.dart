import '../../core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart' show AppTheme;

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ScaffoldPage(
      header: const PageHeader(title: Text('关于')),
      content: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppStyles.primaryColor,
                        AppStyles.primaryColor.withBlue(200),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppStyles.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    FluentIcons.sync_folder,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppConstants.appName,
                  style: theme.typography.title?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppStyles.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'v${AppConstants.appVersion}',
                    style: TextStyle(
                      color: AppStyles.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppConstants.appDescription,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey[120] : Colors.grey[140],
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FluentIcons.check_mark,
                              size: 16,
                              color: AppStyles.successColor,
                            ),
                            const SizedBox(width: 12),
                            Text('主要功能', style: theme.typography.subtitle),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._features.map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: BoxDecoration(
                                    color: AppStyles.primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    f,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FluentIcons.open_source,
                      size: 16,
                      color: isDark ? Colors.grey[100] : Colors.grey[140],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MIT License',
                      style: TextStyle(
                        color: isDark ? Colors.grey[100] : Colors.grey[140],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '本软件遵循MIT开源协议',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[120] : Colors.grey[140],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _features = [
    '本地文件夹与SMB/WebDAV远端同步',
    '支持单向、双向、镜像同步模式',
    '文件版本管理与恢复',
    '定时同步与实时文件监听',
    '冲突检测与智能处理',
    '系统托盘集成，后台静默运行',
  ];
}
