import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/task_provider.dart';
import '../../data/models/sync_task.dart';
import '../../core/constants/enums.dart';
import 'task_edit_page.dart';

/// 任务列表页面
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

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
          label: const Text('新建任务'),
          onPressed: () => _navigateToEdit(null),
        ),
        if (_selectionMode) ...[
          CommandBarButton(
            icon: const Icon(FluentIcons.play),
            label: const Text('批量执行'),
            onPressed: _selectedIds.isEmpty
                ? null
                : () => provider.batchRunSync(_selectedIds.toList()),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.delete),
            label: const Text('批量删除'),
            onPressed:
                _selectedIds.isEmpty ? null : () => _batchDelete(provider),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.cancel),
            label: const Text('取消选择'),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FluentIcons.sync_folder, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('暂无同步任务', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('点击"新建任务"开始创建您的第一个同步任务'),
          const SizedBox(height: 16),
          FilledButton(
            child: const Text('新建任务'),
            onPressed: () => _navigateToEdit(null),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(TaskProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.tasks.length,
      itemBuilder: (context, index) {
        final task = provider.tasks[index];
        return _buildTaskCard(task, provider);
      },
    );
  }

  Widget _buildTaskCard(SyncTask task, TaskProvider provider) {
    final isSelected = _selectedIds.contains(task.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: GestureDetector(
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    checked: isSelected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(task.id);
                      } else {
                        _selectedIds.remove(task.id);
                      }
                    }),
                  ),
                ),
              _buildStatusIcon(task),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${task.localPath} → ${task.remoteProtocol.label}://${task.remoteHost}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[100]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildInfoChip(task.syncDirection.label),
                        const SizedBox(width: 8),
                        _buildInfoChip(task.syncTrigger.label),
                        const SizedBox(width: 8),
                        _buildStatusChip(task.status),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_selectionMode) ...[
                if (task.isRunning)
                  IconButton(
                    icon: const Icon(FluentIcons.pause),
                    onPressed: () => provider.pauseCurrentSync(),
                  )
                else
                  IconButton(
                    icon: const Icon(FluentIcons.play),
                    onPressed:
                        task.isEnabled ? () => provider.runSync(task.id) : null,
                  ),
                IconButton(
                  icon: const Icon(FluentIcons.delete),
                  onPressed: () => _confirmDelete(task, provider),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(SyncTask task) {
    IconData icon;
    Color color;
    switch (task.status) {
      case TaskStatus.syncing:
        icon = FluentIcons.sync;
        color = Colors.blue;
        break;
      case TaskStatus.success:
        icon = FluentIcons.check_mark;
        color = Colors.green;
        break;
      case TaskStatus.failed:
        icon = FluentIcons.error;
        color = Colors.red;
        break;
      case TaskStatus.paused:
        icon = FluentIcons.pause;
        color = Colors.orange;
        break;
      default:
        icon = FluentIcons.clock;
        color = Colors.grey;
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildStatusChip(TaskStatus status) {
    Color color;
    switch (status) {
      case TaskStatus.syncing:
        color = Colors.blue;
        break;
      case TaskStatus.success:
        color = Colors.green;
        break;
      case TaskStatus.failed:
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status.label, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  void _navigateToEdit(SyncTask? task) {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                TaskEditPage(task: task),
          ),
        )
        .then((_) => context.read<TaskProvider>().loadTasks());
  }

  void _confirmDelete(SyncTask task, TaskProvider provider) {
    showDialog(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除任务"${task.name}"吗？'),
        actions: [
          Button(
              child: const Text('取消'), onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('删除'),
            onPressed: () {
              provider.deleteTask(task.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _batchDelete(TaskProvider provider) {
    showDialog(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('确认批量删除'),
        content: Text('确定要删除选中的${_selectedIds.length}个任务吗？'),
        actions: [
          Button(
              child: const Text('取消'), onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('删除'),
            onPressed: () {
              provider.batchDeleteTasks(_selectedIds.toList());
              setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
