import '../../core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../data/models/file_version.dart';
import '../../data/services/version_service.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/sync_task.dart';
import '../../core/theme/app_theme.dart' show AppStyles, ThemeManager;
import '../../shared/widgets/components/indicators.dart';
import '../../shared/widgets/components/dialogs.dart';

class VersionPage extends StatefulWidget {
  const VersionPage({super.key});

  @override
  State<VersionPage> createState() => _VersionPageState();
}

class _VersionPageState extends State<VersionPage> {
  final VersionService _versionService = VersionService();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<SyncTask> _tasks = [];
  String? _selectedTaskId;
  List<String> _filePaths = [];
  String? _selectedFilePath;
  List<FileVersion> _versions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final maps = await _db.getAllTasks();
    setState(() => _tasks = maps.map((m) => SyncTask.fromMap(m)).toList());
  }

  Future<void> _loadFilePaths(String taskId) async {
    setState(() => _loading = true);
    final paths = await _versionService.getUniqueFilePaths(taskId);
    setState(() {
      _filePaths = paths;
      _selectedFilePath = null;
      _versions = [];
      _loading = false;
    });
  }

  Future<void> _loadVersions(String taskId, String filePath) async {
    setState(() => _loading = true);
    final versions = await _versionService.getVersionsForFile(taskId, filePath);
    setState(() {
      _versions = versions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('版本管理'),
        commandBar: CommandBar(
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: () {
                if (_selectedTaskId != null) _loadFilePaths(_selectedTaskId!);
              },
            ),
          ],
        ),
      ),
      content: Row(
        children: [
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ComboBox<String>(
                    value: _selectedTaskId,
                    placeholder: const Text('选择同步任务'),
                    isExpanded: true,
                    items: _tasks
                        .map(
                          (t) => ComboBoxItem(value: t.id, child: Text(t.name)),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedTaskId = v);
                      if (v != null) _loadFilePaths(v);
                    },
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _filePaths.isEmpty
                      ? const Center(child: Text('暂无版本记录'))
                      : ListView.builder(
                          itemCount: _filePaths.length,
                          itemBuilder: (context, index) {
                            final path = _filePaths[index];
                            final isSelected = path == _selectedFilePath;
                            return HoverButton(
                              onPressed: () {
                                setState(() => _selectedFilePath = path);
                                if (_selectedTaskId != null)
                                  _loadVersions(_selectedTaskId!, path);
                              },
                              builder: (context, states) => Container(
                                color: isSelected
                                    ? AppStyles.primaryColor.withValues(
                                        alpha: 0.1,
                                      )
                                    : (states.isHovered
                                          ? (isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.05,
                                                  )
                                                : Colors.grey[20])
                                          : null),
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      FluentIcons.page,
                                      size: 16,
                                      color: isDark
                                          ? Colors.grey[100]
                                          : Colors.grey[140],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            path.split('/').last,
                                            style: TextStyle(
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          Text(
                                            path,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.grey[100]
                                                  : Colors.grey[140],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            color: isDark ? Colors.grey[80] : Colors.grey[40],
          ),
          Expanded(
            child: _loading
                ? const Center(child: ProgressRing())
                : _selectedFilePath == null
                ? const EmptyState(
                    icon: FluentIcons.history,
                    title: '选择文件',
                    subtitle: '从左侧列表选择一个文件查看版本历史',
                  )
                : _buildVersionList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionList() {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(FluentIcons.history),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedFilePath ?? '',
                  style: theme.typography.subtitle,
                ),
              ),
              Text('${_versions.length} 个版本'),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _versions.isEmpty
              ? const Center(child: Text('该文件暂无版本历史'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _versions.length,
                  itemBuilder: (context, index) {
                    final version = _versions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppStyles.primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  'v${version.versionNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppStyles.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    version.versionName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${version.formattedSize} | ${_formatTime(version.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[120],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(FluentIcons.download),
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(FluentIcons.history),
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(FluentIcons.delete),
                              onPressed: () => _deleteVersion(version),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteVersion(FileVersion version) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认删除',
      content: '确定要删除版本 "${version.versionName}" 吗？',
      isDestructive: true,
    );
    if (confirmed) {
      _versionService.deleteVersion(version);
      if (_selectedTaskId != null && _selectedFilePath != null) {
        _loadVersions(_selectedTaskId!, _selectedFilePath!);
      }
    }
  }
}
