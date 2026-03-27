import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sync_target.dart';
import '../../shared/providers/target_provider.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/dialogs.dart';
import '../../shared/widgets/components/indicators.dart';
import 'target_edit_dialog.dart';

class TargetListPage extends StatefulWidget {
  const TargetListPage({super.key});

  @override
  State<TargetListPage> createState() => _TargetListPageState();
}

class _TargetListPageState extends State<TargetListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TargetProvider>();
      provider.loadTargets(refreshStatuses: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TargetProvider>(
      builder: (context, provider, _) {
        final isDark = FluentTheme.of(context).brightness == Brightness.dark;
        final primaryTextColor = isDark ? Colors.white : Colors.black;

        return ScaffoldPage(
          header: PageHeader(
            title: Text(
              '同步目标',
              style: AppStyles.textStyleTitle.copyWith(color: primaryTextColor),
            ),
            commandBar: Align(
              alignment: Alignment.centerRight,
              child: CommandBar(
                primaryItems: [
                  CommandBarButton(
                    icon: const Icon(FluentIcons.add),
                    label: Text(
                      '新建目标',
                      style: AppStyles.textStyleButton.copyWith(
                        color: primaryTextColor,
                      ),
                    ),
                    onPressed: () => _createTarget(context, provider),
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.refresh),
                    label: Text(
                      '刷新在线状态',
                      style: AppStyles.textStyleButton.copyWith(
                        color: primaryTextColor,
                      ),
                    ),
                    onPressed: provider.targets.isEmpty
                        ? null
                        : () => provider.refreshAllStatuses(),
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.settings),
                    label: Text(
                      '探测路径',
                      style: AppStyles.textStyleButton.copyWith(
                        color: primaryTextColor,
                      ),
                    ),
                    onPressed: () => _configureProbePath(context, provider),
                  ),
                ],
              ),
            ),
          ),
          content: provider.isLoading
              ? const Center(child: ProgressRing())
              : provider.targets.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: provider.targets.length,
                  itemBuilder: (context, index) {
                    final target = provider.targets[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildTargetCard(context, provider, target),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: FluentIcons.server,
      title: '暂无同步目标',
      subtitle: '先配置远端目标，再在同步任务中直接选择',
      action: FilledButton(
        child: const Text('创建目标'),
        onPressed: () => _createTarget(context, context.read<TargetProvider>()),
      ),
    );
  }

  Widget _buildTargetCard(
    BuildContext context,
    TargetProvider provider,
    SyncTarget target,
  ) {
    final status = provider.statusOf(target.id);
    final usageCount = provider.usageCountOf(target.id);

    return TaskCard(
      name: target.name,
      description:
          '${target.remoteProtocol.label}://'
          '${target.remoteHost}:${target.remotePort}',
      leading: _buildStatusIcon(status.state),
      badges: [
        _statusBadge(status.state),
        StatusBadge(label: '被 $usageCount 个任务使用', color: AppStyles.infoColor),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(FluentIcons.view),
            onPressed: () => provider.refreshTargetStatus(target.id),
          ),
          IconButton(
            icon: const Icon(FluentIcons.edit),
            onPressed: () => _editTarget(context, target),
          ),
          IconButton(
            icon: const Icon(FluentIcons.delete),
            onPressed: () => _deleteTarget(context, provider, target),
          ),
        ],
      ),
      onTap: () => _editTarget(context, target),
    );
  }

  Widget _buildStatusIcon(TargetOnlineState state) {
    IconData icon;
    Color color;
    switch (state) {
      case TargetOnlineState.online:
        icon = FluentIcons.plug_connected;
        color = AppStyles.successColor;
        break;
      case TargetOnlineState.offline:
        icon = FluentIcons.plug_disconnected;
        color = AppStyles.errorColor;
        break;
      case TargetOnlineState.checking:
        icon = FluentIcons.sync;
        color = AppStyles.warningColor;
        break;
      case TargetOnlineState.unknown:
        icon = FluentIcons.help;
        color = AppStyles.infoColor;
        break;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  StatusBadge _statusBadge(TargetOnlineState state) {
    switch (state) {
      case TargetOnlineState.online:
        return StatusBadge(label: '在线', color: AppStyles.successColor);
      case TargetOnlineState.offline:
        return StatusBadge(label: '离线', color: AppStyles.errorColor);
      case TargetOnlineState.checking:
        return StatusBadge(label: '检测中', color: AppStyles.warningColor);
      case TargetOnlineState.unknown:
        return StatusBadge(label: '未知', color: AppStyles.infoColor);
    }
  }

  Future<void> _createTarget(
    BuildContext context,
    TargetProvider provider,
  ) async {
    await showTargetEditDialog(context);
    if (!context.mounted) return;
    await provider.loadTargets(refreshStatuses: true);
  }

  Future<void> _editTarget(BuildContext context, SyncTarget target) async {
    final provider = context.read<TargetProvider>();
    await showTargetEditDialog(context, target: target);
    if (!context.mounted) return;
    await provider.loadTargets(refreshStatuses: true);
  }

  Future<void> _deleteTarget(
    BuildContext context,
    TargetProvider provider,
    SyncTarget target,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除目标',
      content: '确定删除目标“${target.name}”吗？',
      isDestructive: true,
    );

    if (!confirmed || !context.mounted) return;

    final success = await provider.deleteTarget(target.id);
    if (!context.mounted || success) return;

    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('删除失败'),
        content: Text(provider.error ?? '该目标可能正在被任务使用'),
        severity: InfoBarSeverity.error,
      ),
    );
  }

  Future<void> _configureProbePath(
    BuildContext context,
    TargetProvider provider,
  ) async {
    final controller = TextEditingController(
      text: provider.defaultWebDavProbePath,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('默认探测路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('用于“刷新在线状态”与自动在线检测（WebDAV）。'),
            const SizedBox(height: 10),
            TextBox(controller: controller, placeholder: '/shared/folder'),
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存并刷新'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    provider.setDefaultWebDavProbePath(controller.text);
    await provider.refreshAllStatuses();
  }
}
