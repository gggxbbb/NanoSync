import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/task_provider.dart';
import '../../data/models/sync_task.dart';
import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/indicators.dart';
import '../../shared/widgets/components/dialogs.dart';
import 'task_edit_page.dart' show showTaskEditDialog;

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TaskProvider>().loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('同步任务'),
            commandBar: _buildCommandBar(provider),
          ),
          content: provider.isLoading
              ? const Center(child: ProgressRing())
              : provider.tasks.isEmpty
              ? _buildEmptyState()
              : _buildTaskList(provider),
        );
      },
    );
  }

  Widget _buildCommandBar(TaskProvider provider) {
    return CommandBar(
      primaryItems: [
        CommandBarButton(
          icon: const Icon(FluentIcons.add),
          label: const Text('新建'),
          onPressed: () => _navigateToEdit(null),
        ),
        CommandBarButton(
          icon: const Icon(FluentIcons.search),
          label: const Text('搜索'),
          onPressed: () => _showSearch(),
        ),
        if (_selectionMode) ...[
          const CommandBarSeparator(),
          CommandBarButton(
            icon: const Icon(FluentIcons.play),
            label: const Text('执行'),
            onPressed: _selectedIds.isEmpty
                ? null
                : () => provider.batchRunSync(_selectedIds.toList()),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.delete),
            label: const Text('删除'),
            onPressed: _selectedIds.isEmpty
                ? null
                : () => _batchDelete(provider),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.cancel),
            label: const Text('取消'),
            onPressed: () => setState(() {
              _selectionMode = false;
              _selectedIds.clear();
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: FluentIcons.sync_folder,
      title: '暂无同步任务',
      subtitle: '点击"新建"按钮创建您的第一个同步任务',
      action: FilledButton(
        onPressed: () => _navigateToEdit(null),
        child: const Text('新建任务'),
      ),
    );
  }

  Widget _buildTaskList(TaskProvider provider) {
    final filteredTasks = _searchQuery.isEmpty
        ? provider.tasks
        : provider.tasks
              .where(
                (t) =>
                    t.name.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

    final runningTasks = filteredTasks.where((t) => t.isRunning).toList();
    final idleTasks = filteredTasks
        .where((t) => !t.isRunning && t.status == TaskStatus.idle)
        .toList();
    final completedTasks = filteredTasks
        .where(
          (t) =>
              t.status == TaskStatus.success || t.status == TaskStatus.failed,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (runningTasks.isNotEmpty) ...[
          const SectionHeader(title: '正在同步'),
          ...runningTasks.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildTaskCard(t, provider),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (idleTasks.isNotEmpty) ...[
          const SectionHeader(title: '等待中'),
          ...idleTasks.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildTaskCard(t, provider),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (completedTasks.isNotEmpty) ...[
          const SectionHeader(title: '已完成'),
          ...completedTasks.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildTaskCard(t, provider),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTaskCard(SyncTask task, TaskProvider provider) {
    final isSelected = _selectedIds.contains(task.id);
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TaskCard(
      name: task.name,
      description:
          '${task.localPath} → ${task.remoteProtocol.label}://${task.remoteHost}',
      isSelected: isSelected,
      isRunning: task.isRunning,
      progress: task.syncProgress,
      leading: _buildStatusIcon(task),
      badges: [
        StatusBadge(
          label: task.syncDirection.label,
          color: AppStyles.infoColor,
        ),
        StatusBadge(
          label: task.syncTrigger.label,
          color: AppStyles.primaryColor,
        ),
        _buildStatusBadge(task.status),
      ],
      trailing: _selectionMode
          ? Checkbox(
              checked: isSelected,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedIds.add(task.id);
                } else {
                  _selectedIds.remove(task.id);
                }
              }),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (task.isRunning)
                  IconButton(
                    icon: Icon(
                      FluentIcons.pause,
                      color: AppStyles.warningColor,
                    ),
                    onPressed: () => provider.pauseCurrentSync(),
                  )
                else
                  IconButton(
                    icon: Icon(FluentIcons.play, color: AppStyles.successColor),
                    onPressed: task.isEnabled
                        ? () => provider.runSync(task.id)
                        : null,
                  ),
                IconButton(
                  icon: Icon(
                    FluentIcons.delete,
                    color: isDark ? Colors.grey[100] : Colors.grey[140],
                  ),
                  onPressed: () => _confirmDelete(task, provider),
                ),
              ],
            ),
      onTap: () {
        if (_selectionMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(task.id);
            } else {
              _selectedIds.add(task.id);
            }
          });
        } else {
          _navigateToEdit(task);
        }
      },
      onLongPress: () {
        setState(() {
          _selectionMode = true;
          _selectedIds.add(task.id);
        });
      },
    );
  }

  Widget _buildStatusIcon(SyncTask task) {
    IconData icon;
    Color color;
    switch (task.status) {
      case TaskStatus.syncing:
        icon = FluentIcons.sync;
        color = AppStyles.primaryColor;
        break;
      case TaskStatus.success:
        icon = FluentIcons.check_mark;
        color = AppStyles.successColor;
        break;
      case TaskStatus.failed:
        icon = FluentIcons.error_badge;
        color = AppStyles.errorColor;
        break;
      case TaskStatus.paused:
        icon = FluentIcons.pause;
        color = AppStyles.warningColor;
        break;
      default:
        icon = FluentIcons.clock;
        color = AppStyles.infoColor;
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildStatusBadge(TaskStatus status) {
    Color color;
    switch (status) {
      case TaskStatus.syncing:
        color = AppStyles.primaryColor;
        break;
      case TaskStatus.success:
        color = AppStyles.successColor;
        break;
      case TaskStatus.failed:
        color = AppStyles.errorColor;
        break;
      case TaskStatus.paused:
        color = AppStyles.warningColor;
        break;
      default:
        color = AppStyles.infoColor;
    }
    return StatusBadge(label: status.label, color: color);
  }

  void _showSearch() {
    final controller = TextEditingController(text: _searchQuery);
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('搜索任务'),
        content: TextBox(
          controller: controller,
          placeholder: '输入任务名称...',
          autofocus: true,
          onChanged: (v) => _searchQuery = v,
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('搜索'),
            onPressed: () {
              setState(() => _searchQuery = controller.text);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(SyncTask? task) {
    showTaskEditDialog(
      context,
      task: task,
    ).then((_) => context.read<TaskProvider>().loadTasks());
  }

  Future<void> _confirmDelete(SyncTask task, TaskProvider provider) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认删除',
      content: '确定要删除任务"${task.name}"吗？',
      isDestructive: true,
    );
    if (confirmed) {
      provider.deleteTask(task.id);
    }
  }

  Future<void> _batchDelete(TaskProvider provider) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '批量删除',
      content: '确定要删除选中的${_selectedIds.length}个任务吗？',
      isDestructive: true,
    );
    if (confirmed) {
      provider.batchDeleteTasks(_selectedIds.toList());
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
    }
  }
}
