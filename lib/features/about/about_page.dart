import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants/app_constants.dart';

/// 关于页面
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('关于')),
      content: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(FluentIcons.sync_folder,
                    size: 48, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                AppConstants.appName,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'v${AppConstants.appVersion}',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text(
                AppConstants.appDescription,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('主要功能',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildFeatureItem('本地文件夹与SMB/WebDAV远端同步'),
                      _buildFeatureItem('支持单向、双向、镜像同步模式'),
                      _buildFeatureItem('文件版本管理与恢复'),
                      _buildFeatureItem('定时同步与实时文件监听'),
                      _buildFeatureItem('冲突检测与智能处理'),
                      _buildFeatureItem('系统托盘集成，后台静默运行'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('MIT License', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              const Text(
                '本软件遵循MIT开源协议，所有依赖库均为宽松协议。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(FluentIcons.check_mark, size: 14, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
