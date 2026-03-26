import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/task_provider.dart';
import '../../data/models/sync_task.dart';
import '../../core/constants/enums.dart';

/// 实时监控页面
class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final runningTasks = provider.runningTasks;
        final recentTasks = provider.tasks
            .where((t) => t.lastSyncTime != null)
            .take(10)
            .toList();

        return ScaffoldPage(
          header: const PageHeader(title: Text('实时监控')),
          content: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusOverview(provider),
                const SizedBox(height: 24),
                if (runningTasks.isNotEmpty) ...[
                  const Text('正在同步',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...runningTasks.map((t) => _buildRunningTaskCard(t)),
                  const SizedBox(height: 24),
                ],
                const Text('最近同步',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (recentTasks.isEmpty)
                  const Card(child: Text('暂无同步记录'))
                else
                  ...recentTasks.map((t) => _buildRecentTaskCard(t, provider)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusOverview(TaskProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _buildStatCard(
                '总任务', provider.tasks.length.toString(), FluentIcons.task_list),
            _buildStatCard('运行中', provider.runningTasks.length.toString(),
                FluentIcons.sync),
            _buildStatCard('已启用', provider.enabledTasks.length.toString(),
                FluentIcons.check_mark),
            _buildStatCard(
                '已禁用',
                (provider.tasks.length - provider.enabledTasks.length)
                    .toString(),
                FluentIcons.cancel),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 28, color: Colors.blue),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRunningTaskCard(SyncTask task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ProgressRing(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(task.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Text('${(task.syncProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ProgressBar(value: task.syncProgress * 100),
            const SizedBox(height: 8),
            Text('${task.localPath} → ${task.remoteHost}:${task.remotePath}',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTaskCard(SyncTask task, TaskProvider provider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              task.status == TaskStatus.success
                  ? FluentIcons.check_mark
                  : task.status == TaskStatus.failed
                      ? FluentIcons.error
                      : FluentIcons.clock,
              color: task.status == TaskStatus.success
                  ? Colors.green
                  : task.status == TaskStatus.failed
                      ? Colors.red
                      : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.name),
                  Text(task.lastSyncTime != null
                      ? '上次同步: ${_formatTime(task.lastSyncTime!)}'
                      : '从未同步'),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.play),
              onPressed:
                  task.isRunning ? null : () => provider.runSync(task.id),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
