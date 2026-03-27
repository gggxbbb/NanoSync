import '../../core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/task_provider.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/indicators.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final isDark = FluentTheme.of(context).brightness == Brightness.dark;
        final primaryTextColor = isDark ? Colors.white : Colors.black;

        return ScaffoldPage(
          header: PageHeader(
            title: Text(
              '实时监控',
              style: AppStyles.textStyleTitle.copyWith(color: primaryTextColor),
            ),
          ),
          content: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsGrid(context, provider),
                const SizedBox(height: 24),
                if (provider.runningTasks.isNotEmpty) ...[
                  const SectionHeader(title: '正在同步'),
                  ...provider.runningTasks.map(
                    (t) => _buildRunningTaskCard(t, isDark),
                  ),
                  const SizedBox(height: 24),
                ],
                const SectionHeader(title: '最近同步', subtitle: '显示最近同步的任务'),
                const SizedBox(height: 12),
                if (provider.tasks.where((t) => t.lastSyncTime != null).isEmpty)
                  _buildEmptyCard(isDark)
                else
                  ...provider.tasks
                      .where((t) => t.lastSyncTime != null)
                      .take(10)
                      .map(
                        (t) =>
                            _buildRecentTaskCard(context, t, provider, isDark),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppStyles.darkCard.withValues(alpha: 0.85)
            : AppStyles.lightCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppStyles.borderColor(isDark)),
      ),
      child: Text(
        '暂无同步记录',
        style: AppStyles.textStyleBody.copyWith(
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, TaskProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
        final itemWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * 16) / crossAxisCount;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.all_apps,
                title: '总任务',
                value: provider.tasks.length.toString(),
                iconColor: AppStyles.primaryColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.sync,
                title: '运行中',
                value: provider.runningTasks.length.toString(),
                iconColor: AppStyles.infoColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.check_mark,
                title: '已启用',
                value: provider.enabledTasks.length.toString(),
                iconColor: AppStyles.successColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.cancel,
                title: '已禁用',
                value: (provider.tasks.length - provider.enabledTasks.length)
                    .toString(),
                iconColor: AppStyles.errorColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRunningTaskCard(task, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppStyles.darkCard.withValues(alpha: 0.85)
            : AppStyles.lightCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppStyles.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.name,
                  style: AppStyles.textStyleBody.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Text(
                '${(task.syncProgress * 100).toStringAsFixed(0)}%',
                style: AppStyles.textStyleBody.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(value: task.syncProgress * 100),
          const SizedBox(height: 8),
          Text(
            '${task.localPath} → ${task.remoteHost}:${task.remotePath}',
            style: AppStyles.textStyleCaption.copyWith(
              color: isDark ? Colors.grey[100] : Colors.grey[140],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTaskCard(
    BuildContext context,
    task,
    TaskProvider provider,
    bool isDark,
  ) {
    return TaskCard(
      name: task.name,
      description: task.lastSyncTime != null
          ? '上次同步: ${_formatTime(task.lastSyncTime!)}'
          : '从未同步',
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color:
              (task.status.label == '同步成功'
                      ? AppStyles.successColor
                      : task.status.label == '同步失败'
                      ? AppStyles.errorColor
                      : AppStyles.infoColor)
                  .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          task.status.label == '同步成功'
              ? FluentIcons.check_mark
              : task.status.label == '同步失败'
              ? FluentIcons.error_badge
              : FluentIcons.clock,
          color: task.status.label == '同步成功'
              ? AppStyles.successColor
              : task.status.label == '同步失败'
              ? AppStyles.errorColor
              : AppStyles.infoColor,
          size: 22,
        ),
      ),
      trailing: IconButton(
        icon: Icon(FluentIcons.play, color: AppStyles.successColor),
        onPressed: task.isRunning ? null : () => provider.runSync(task.id),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
