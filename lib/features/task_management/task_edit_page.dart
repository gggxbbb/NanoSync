import '../../core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../data/models/sync_task.dart';
import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/task_provider.dart';
import '../../data/services/webdav_service.dart';

Future<void> showTaskEditDialog(BuildContext context, {SyncTask? task}) async {
  await showDialog(
    context: context,
    builder: (context) => TaskEditDialog(task: task),
  );
}

class TaskEditDialog extends StatefulWidget {
  final SyncTask? task;
  const TaskEditDialog({super.key, this.task});

  @override
  State<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<TaskEditDialog> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  late TextEditingController _nameCtrl;
  late TextEditingController _localPathCtrl;
  late TextEditingController _remoteHostCtrl;
  late TextEditingController _remotePortCtrl;
  late TextEditingController _remoteUserCtrl;
  late TextEditingController _remotePassCtrl;
  late TextEditingController _remotePathCtrl;
  late TextEditingController _excludeExtCtrl;
  late TextEditingController _excludeFolderCtrl;
  late TextEditingController _excludePatternCtrl;
  late TextEditingController _scheduleIntervalCtrl;
  late TextEditingController _scheduleTimeCtrl;

  RemoteProtocol _remoteProtocol = RemoteProtocol.smb;
  SyncDirection _syncDirection = SyncDirection.localToRemote;
  SyncTrigger _syncTrigger = SyncTrigger.manual;
  ScheduleType _scheduleType = ScheduleType.hours;
  ConflictStrategy _conflictStrategy = ConflictStrategy.keepBoth;
  bool _isEnabled = true;
  bool _testingConnection = false;
  String? _connectionTestResult;

  bool get isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _nameCtrl = TextEditingController(text: task?.name ?? '');
    _localPathCtrl = TextEditingController(text: task?.localPath ?? '');
    _remoteHostCtrl = TextEditingController(text: task?.remoteHost ?? '');
    _remotePortCtrl = TextEditingController(
      text: (task?.remotePort ?? 445).toString(),
    );
    _remoteUserCtrl = TextEditingController(text: task?.remoteUsername ?? '');
    _remotePassCtrl = TextEditingController(text: task?.remotePassword ?? '');
    _remotePathCtrl = TextEditingController(text: task?.remotePath ?? '/');
    _excludeExtCtrl = TextEditingController(
      text: task?.excludeExtensions.join(', ') ?? '',
    );
    _excludeFolderCtrl = TextEditingController(
      text: task?.excludeFolders.join(', ') ?? '',
    );
    _excludePatternCtrl = TextEditingController(
      text: task?.excludePatterns.join(', ') ?? '',
    );
    _scheduleIntervalCtrl = TextEditingController(
      text: (task?.scheduleInterval ?? 1).toString(),
    );
    _scheduleTimeCtrl = TextEditingController(
      text: task?.scheduleTime ?? '00:00',
    );
    _remoteProtocol = task?.remoteProtocol ?? RemoteProtocol.smb;
    _syncDirection = task?.syncDirection ?? SyncDirection.localToRemote;
    _syncTrigger = task?.syncTrigger ?? SyncTrigger.manual;
    _scheduleType = task?.scheduleType ?? ScheduleType.hours;
    _conflictStrategy = task?.conflictStrategy ?? ConflictStrategy.keepBoth;
    _isEnabled = task?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _localPathCtrl.dispose();
    _remoteHostCtrl.dispose();
    _remotePortCtrl.dispose();
    _remoteUserCtrl.dispose();
    _remotePassCtrl.dispose();
    _remotePathCtrl.dispose();
    _excludeExtCtrl.dispose();
    _excludeFolderCtrl.dispose();
    _excludePatternCtrl.dispose();
    _scheduleIntervalCtrl.dispose();
    _scheduleTimeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final steps = ['基本信息', '远端配置', '同步规则', '定时策略'];

    return ContentDialog(
      title: Row(
        children: [
          Text(
            isEditing ? '编辑同步任务' : '新建同步任务',
            style: AppStyles.textStyleSubtitle,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(FluentIcons.chrome_close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
      content: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildStepIndicator(steps, isDark),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: [
                  _buildBasicInfoStep(),
                  _buildRemoteConfigStep(),
                  _buildSyncRulesStep(),
                  _buildScheduleStep(),
                ][_currentStep],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_currentStep > 0)
              SizedBox(
                width: 100,
                child: Button(
                  child: const Text('上一步'),
                  onPressed: () => setState(() => _currentStep--),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: _currentStep < 3
                  ? FilledButton(
                      child: const Text('下一步'),
                      onPressed: () => setState(() => _currentStep++),
                    )
                  : FilledButton(
                      child: Text(isEditing ? '保存修改' : '创建任务'),
                      onPressed: _saveTask,
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepIndicator(List<String> steps, bool isDark) {
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == _currentStep;
        final isCompleted = i < _currentStep;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _currentStep = i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? AppStyles.primaryColor
                        : isCompleted
                        ? AppStyles.successColor
                        : Colors.grey[60]!,
                    width: isActive ? 3 : 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isCompleted)
                    Icon(
                      FluentIcons.check_mark,
                      size: 14,
                      color: AppStyles.successColor,
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppStyles.primaryColor
                            : Colors.grey[60],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isActive
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    steps[i],
                    style: TextStyle(
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isActive
                          ? AppStyles.primaryColor
                          : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBasicInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '任务名称',
          child: TextFormBox(
            controller: _nameCtrl,
            placeholder: '请输入任务名称',
            validator: (v) => (v == null || v.isEmpty) ? '请输入任务名称' : null,
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '本地文件夹',
          child: Row(
            children: [
              Expanded(
                child: TextFormBox(
                  controller: _localPathCtrl,
                  placeholder: '请选择本地文件夹路径',
                  readOnly: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '请选择本地文件夹' : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                child: const Text('选择'),
                onPressed: _pickLocalFolder,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '同步方向',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ComboBox<SyncDirection>(
                value: _syncDirection,
                items: SyncDirection.values
                    .map((d) => ComboBoxItem(value: d, child: Text(d.label)))
                    .toList(),
                onChanged: (v) => setState(() => _syncDirection = v!),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FluentTheme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey[20],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getSyncDirectionDescription(_syncDirection),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ToggleSwitch(
          checked: _isEnabled,
          onChanged: (v) => setState(() => _isEnabled = v),
          content: const Text('启用任务'),
        ),
      ],
    );
  }

  String _getSyncDirectionDescription(SyncDirection direction) {
    switch (direction) {
      case SyncDirection.localToRemote:
        return '单向同步：仅将本地文件上传到远端，不删除远端多余文件。适合备份场景。';
      case SyncDirection.remoteToLocal:
        return '单向同步：仅将远端文件下载到本地，不删除本地多余文件。适合从服务器拉取更新。';
      case SyncDirection.bidirectional:
        return '双向同步：本地和远端双向同步，保持两边文件一致。新文件互相复制，删除操作也会同步。';
      case SyncDirection.mirror:
        return '镜像同步：让远端完全镜像本地，删除远端本地不存在的文件。谨慎使用，会删除远端文件。';
      case SyncDirection.localOnly:
        return '仅本地：不连接远端，仅对本地文件夹启用版本管理。适合在不同步的情况下保留文件历史记录。';
    }
  }

  Widget _buildRemoteConfigStep() {
    if (_syncDirection == SyncDirection.localOnly) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluentTheme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey[20],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(FluentIcons.info, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '仅本地模式无需配置远端连接，此步骤将被跳过。',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '远端协议',
          child: ComboBox<RemoteProtocol>(
            value: _remoteProtocol,
            items: RemoteProtocol.values
                .map((p) => ComboBoxItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) => setState(() {
              _remoteProtocol = v!;
              _remotePortCtrl.text = v == RemoteProtocol.webdav ? '443' : '445';
            }),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '服务器地址',
          child: TextFormBox(
            controller: _remoteHostCtrl,
            placeholder: '例如: 192.168.1.100',
            validator: (v) => (v == null || v.isEmpty) ? '请输入服务器地址' : null,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: '端口',
                child: TextFormBox(
                  controller: _remotePortCtrl,
                  placeholder: '445',
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InfoLabel(
                label: '用户名',
                child: TextFormBox(
                  controller: _remoteUserCtrl,
                  placeholder: '请输入用户名',
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '请输入用户名' : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '密码',
          child:
              PasswordBox(controller: _remotePassCtrl, placeholder: '请输入密码'),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '远端路径',
          child: TextFormBox(
            controller: _remotePathCtrl,
            placeholder: '/shared/folder',
            validator: (v) => (v == null || v.isEmpty) ? '请输入远端路径' : null,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: _testingConnection ? null : _testConnection,
              child: _testingConnection
                  ? const SizedBox(
                      width: 16, height: 16, child: ProgressRing())
                  : const Text('测试连接'),
            ),
            const SizedBox(width: 16),
            if (_connectionTestResult != null)
              Flexible(
                child: Text(
                  _connectionTestResult!,
                  style: TextStyle(
                    color: _connectionTestResult!.contains('成功')
                        ? AppStyles.successColor
                        : AppStyles.errorColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSyncRulesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '冲突处理策略',
          child: ComboBox<ConflictStrategy>(
            value: _conflictStrategy,
            items: ConflictStrategy.values
                .map((s) => ComboBoxItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (v) => setState(() => _conflictStrategy = v!),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '排除扩展名（逗号分隔）',
          child: TextFormBox(
            controller: _excludeExtCtrl,
            placeholder: '.tmp, .bak, .log',
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '排除文件夹（逗号分隔）',
          child: TextFormBox(
            controller: _excludeFolderCtrl,
            placeholder: '.git, node_modules, .vscode',
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: '排除模式（正则表达式，逗号分隔）',
          child: TextFormBox(
            controller: _excludePatternCtrl,
            placeholder: r'.*\.tmp$',
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '同步触发方式',
          child: ComboBox<SyncTrigger>(
            value: _syncTrigger,
            items: SyncTrigger.values
                .map((t) => ComboBoxItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) => setState(() => _syncTrigger = v!),
          ),
        ),
        if (_syncTrigger == SyncTrigger.scheduled) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InfoLabel(
                  label: '定时周期',
                  child: ComboBox<ScheduleType>(
                    value: _scheduleType,
                    items: ScheduleType.values
                        .map(
                          (t) => ComboBoxItem(value: t, child: Text(t.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _scheduleType = v!),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InfoLabel(
                  label: '间隔',
                  child: TextFormBox(
                    controller: _scheduleIntervalCtrl,
                    placeholder: '1',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: '指定时间（HH:mm）',
            child: TextFormBox(
              controller: _scheduleTimeCtrl,
              placeholder: '00:00',
            ),
          ),
        ],
        if (_syncTrigger == SyncTrigger.realtime) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey[20],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '实时同步将监听本地文件夹变更，文件变更后自动同步到远端。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickLocalFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) _localPathCtrl.text = result;
  }

  Future<void> _testConnection() async {
    if (_remoteHostCtrl.text.isEmpty) {
      setState(() => _connectionTestResult = '请先填写服务器地址');
      return;
    }
    if (_remoteUserCtrl.text.isEmpty) {
      setState(() => _connectionTestResult = '请先填写用户名');
      return;
    }

    setState(() {
      _testingConnection = true;
      _connectionTestResult = null;
    });

    try {
      final tempTask = _buildTaskFromForm();
      final webdavService = WebDAVService();
      final result = await webdavService.testConnection(tempTask);

      setState(() {
        _testingConnection = false;
        if (result.success) {
          _connectionTestResult = '连接测试成功';
        } else {
          _connectionTestResult = result.error ?? '连接测试失败';
        }
      });
    } catch (e) {
      setState(() {
        _testingConnection = false;
        _connectionTestResult = '连接测试失败: $e';
      });
    }
  }

  SyncTask _buildTaskFromForm() {
    return SyncTask(
      id: widget.task?.id,
      name: _nameCtrl.text,
      localPath: _localPathCtrl.text,
      remoteProtocol: _remoteProtocol,
      remoteHost: _remoteHostCtrl.text,
      remotePort: int.tryParse(_remotePortCtrl.text) ?? 445,
      remoteUsername: _remoteUserCtrl.text,
      remotePassword: _remotePassCtrl.text,
      remotePath: _remotePathCtrl.text,
      syncDirection: _syncDirection,
      syncTrigger: _syncTrigger,
      scheduleType: _syncTrigger == SyncTrigger.scheduled
          ? _scheduleType
          : null,
      scheduleInterval: _syncTrigger == SyncTrigger.scheduled
          ? int.tryParse(_scheduleIntervalCtrl.text)
          : null,
      scheduleTime: _scheduleTimeCtrl.text,
      conflictStrategy: _conflictStrategy,
      isEnabled: _isEnabled,
      excludeExtensions: _excludeExtCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      excludeFolders: _excludeFolderCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      excludePatterns: _excludePatternCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    final task = _buildTaskFromForm();
    final provider = context.read<TaskProvider>();
    bool success;
    if (isEditing) {
      success = await provider.updateTask(task);
    } else {
      final result = await provider.addTask(task);
      success = result != null;
    }
    if (success && mounted) Navigator.pop(context);
  }
}
