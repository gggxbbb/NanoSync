import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sync_task.dart';
import '../../shared/providers/task_provider.dart';
import '../../shared/providers/target_provider.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/indicators.dart';

/// Dashboard：合并实时监控与总览
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TaskProvider>().loadTasks();
      context.read<TargetProvider>().loadTargets(refreshStatuses: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<TaskProvider, TargetProvider>(
      builder: (context, taskProvider, targetProvider, _) {
        final isDark = FluentTheme.of(context).brightness == Brightness.dark;
        final primaryTextColor = isDark ? Colors.white : Colors.black;
        final totalTargets = targetProvider.targets.length;
        final onlineTargets = targetProvider.targets
            .where(
              (t) =>
                  targetProvider.statusOf(t.id).state ==
                  TargetOnlineState.online,
            )
            .length;
        final offlineTargets = targetProvider.targets
            .where(
              (t) =>
                  targetProvider.statusOf(t.id).state ==
                  TargetOnlineState.offline,
            )
            .length;
        final checkingTargets = targetProvider.targets
            .where(
              (t) =>
                  targetProvider.statusOf(t.id).state ==
                  TargetOnlineState.checking,
            )
            .length;
        final onlineRate = totalTargets == 0
            ? 0
            : ((onlineTargets / totalTargets) * 100).round();

        return ScaffoldPage(
          header: PageHeader(
            title: Text(
              '仪表盘',
              style: AppStyles.textStyleTitle.copyWith(color: primaryTextColor),
            ),
            commandBar: Align(
              alignment: Alignment.centerRight,
              child: CommandBar(
                primaryItems: [
                  CommandBarButton(
                    icon: const Icon(FluentIcons.refresh),
                    label: Text(
                      '刷新',
                      style: AppStyles.textStyleButton.copyWith(
                        color: primaryTextColor,
                      ),
                    ),
                    onPressed: () async {
                      await taskProvider.loadTasks();
                      await targetProvider.loadTargets(refreshStatuses: true);
                    },
                  ),
                ],
              ),
            ),
          ),
          content: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsGrid(
                  taskProvider,
                  targetProvider,
                  onlineTargets,
                  offlineTargets,
                  checkingTargets,
                  onlineRate,
                ),
                const SizedBox(height: 24),
                if (taskProvider.runningTasks.isNotEmpty) ...[
                  const SectionHeader(title: '正在同步'),
                  ...taskProvider.runningTasks.map(
                    (task) =>
                        _buildRunningTaskCard(task, targetProvider, isDark),
                  ),
                  const SizedBox(height: 24),
                ],
                SectionHeader(
                  title: '目标在线状态',
                  subtitle:
                      '在线 $onlineTargets / 离线 $offlineTargets / 检测中 $checkingTargets',
                ),
                const SizedBox(height: 12),
                if (targetProvider.targets.isEmpty)
                  _buildEmptyCard('暂无目标配置', isDark)
                else
                  ...(targetProvider.targets.toList()..sort(
                        (a, b) =>
                            _statusPriority(
                              targetProvider.statusOf(b.id).state,
                            ).compareTo(
                              _statusPriority(
                                targetProvider.statusOf(a.id).state,
                              ),
                            ),
                      ))
                      .take(8)
                      .map(
                        (target) => _buildTargetStatusCard(
                          target.name,
                          targetProvider.statusOf(target.id),
                          isDark,
                        ),
                      ),
                const SizedBox(height: 24),
                const SectionHeader(title: '最近同步', subtitle: '显示最近同步任务'),
                const SizedBox(height: 12),
                if (taskProvider.tasks
                    .where((t) => t.lastSyncTime != null)
                    .isEmpty)
                  _buildEmptyCard('暂无同步记录', isDark)
                else
                  ...taskProvider.tasks
                      .where((t) => t.lastSyncTime != null)
                      .take(8)
                      .map(
                        (t) => _buildRecentTaskCard(
                          taskProvider,
                          targetProvider,
                          t,
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsGrid(
    TaskProvider taskProvider,
    TargetProvider targetProvider,
    int onlineTargets,
    int offlineTargets,
    int checkingTargets,
    int onlineRate,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 6
            : (constraints.maxWidth > 900 ? 4 : 2);
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
                title: '同步任务',
                value: taskProvider.tasks.length.toString(),
                iconColor: AppStyles.primaryColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.sync,
                title: '运行中任务',
                value: taskProvider.runningTasks.length.toString(),
                iconColor: AppStyles.infoColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.server,
                title: '同步目标',
                value: targetProvider.targets.length.toString(),
                iconColor: AppStyles.warningColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.plug_connected,
                title: '在线目标',
                value: onlineTargets.toString(),
                iconColor: AppStyles.successColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.plug_disconnected,
                title: '离线目标',
                value: offlineTargets.toString(),
                iconColor: AppStyles.errorColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.processing,
                title: '检测中目标',
                value: checkingTargets.toString(),
                iconColor: AppStyles.warningColor,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: InfoCard(
                icon: FluentIcons.single_column,
                title: '在线率',
                value: '$onlineRate%',
                iconColor: AppStyles.primaryColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRunningTaskCard(
    SyncTask task,
    TargetProvider targetProvider,
    bool isDark,
  ) {
    final targetName = _resolveTargetName(task, targetProvider);
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = AppStyles.lightTextSecondary(isDark);

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
                width: 18,
                height: 18,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.name,
                  style: AppStyles.textStyleBody.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
              ),
              Text(
                '${(task.syncProgress * 100).toStringAsFixed(0)}%',
                style: AppStyles.textStyleBody.copyWith(
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '目标：$targetName',
            style: AppStyles.textStyleCaption.copyWith(
              color: secondaryTextColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          ProgressBar(value: task.syncProgress * 100),
        ],
      ),
    );
  }

  Widget _buildTargetStatusCard(
    String targetName,
    TargetStatusInfo status,
    bool isDark,
  ) {
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = AppStyles.lightTextSecondary(isDark);
    final (label, color) = switch (status.state) {
      TargetOnlineState.online => ('在线', AppStyles.successColor),
      TargetOnlineState.offline => ('离线', AppStyles.errorColor),
      TargetOnlineState.checking => ('检测中', AppStyles.warningColor),
      TargetOnlineState.unknown => ('未知', AppStyles.infoColor),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppStyles.darkCard.withValues(alpha: 0.85)
            : AppStyles.lightCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppStyles.borderColor(isDark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetName,
                  style: AppStyles.textStyleBody.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message ?? '无详细信息',
                  style: AppStyles.textStyleCaption.copyWith(
                    color: secondaryTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: AppStyles.textStyleBody.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatCheckedAt(status.lastCheckedAt),
                style: AppStyles.textStyleCaption.copyWith(
                  fontSize: 11,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTaskCard(
    TaskProvider provider,
    TargetProvider targetProvider,
    SyncTask task,
  ) {
    final targetName = _resolveTargetName(task, targetProvider);
    final syncTimeText = task.lastSyncTime != null
        ? '上次同步: ${_formatTime(task.lastSyncTime!)}'
        : '从未同步';

    return TaskCard(
      name: task.name,
      description: '目标: $targetName · $syncTimeText',
      leading: const Icon(FluentIcons.history),
      trailing: IconButton(
        icon: const Icon(FluentIcons.play, color: AppStyles.successColor),
        onPressed: task.isRunning ? null : () => provider.runSync(task.id),
      ),
    );
  }

  Widget _buildEmptyCard(String text, bool isDark) {
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppStyles.darkCard.withValues(alpha: 0.85)
            : AppStyles.lightCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppStyles.borderColor(isDark)),
      ),
      child: Text(
        text,
        style: AppStyles.textStyleBody.copyWith(color: primaryTextColor),
      ),
    );
  }

  String _resolveTargetName(SyncTask task, TargetProvider targetProvider) {
    final target = targetProvider.getTarget(task.targetId);
    if (target != null) {
      return target.name;
    }
    if (task.targetId != null && task.targetId!.isNotEmpty) {
      return '目标已删除';
    }
    return '未选择目标';
  }

  int _statusPriority(TargetOnlineState state) {
    return switch (state) {
      TargetOnlineState.offline => 3,
      TargetOnlineState.checking => 2,
      TargetOnlineState.unknown => 1,
      TargetOnlineState.online => 0,
    };
  }

  String _formatCheckedAt(DateTime? time) {
    if (time == null) return '未检测';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
