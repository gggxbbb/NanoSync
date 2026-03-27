import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sync_target.dart';
import '../../data/models/sync_task.dart';
import '../../shared/providers/target_provider.dart';
import '../../shared/providers/task_provider.dart';
import '../../shared/widgets/components/safe_combo_box.dart';
import 'target_edit_dialog.dart';

Future<void> showTaskEditDialog(BuildContext context, {SyncTask? task}) async {
  await showDialog(
    context: context,
    builder: (context) => TaskEditDialog(task: task),
  );
}

class TaskEditDialog extends StatefulWidget {
  const TaskEditDialog({super.key, this.task});

  final SyncTask? task;

  @override
  State<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<TaskEditDialog> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  late TextEditingController _nameCtrl;
  late TextEditingController _localPathCtrl;
  late TextEditingController _remotePathCtrl;
  late TextEditingController _excludeExtCtrl;
  late TextEditingController _excludeFolderCtrl;
  late TextEditingController _excludePatternCtrl;
  late TextEditingController _scheduleIntervalCtrl;
  late TextEditingController _scheduleTimeCtrl;

  SyncDirection _syncDirection = SyncDirection.bidirectional;
  SyncTrigger _syncTrigger = SyncTrigger.manual;
  ScheduleType _scheduleType = ScheduleType.hours;
  ConflictStrategy _conflictStrategy = ConflictStrategy.keepBoth;
  bool _isEnabled = true;
  String? _selectedTargetId;

  bool get isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _nameCtrl = TextEditingController(text: task?.name ?? '');
    _localPathCtrl = TextEditingController(text: task?.localPath ?? '');
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

    final existingDirection =
        task?.syncDirection ?? SyncDirection.bidirectional;
    _syncDirection = existingDirection == SyncDirection.localOnly
        ? SyncDirection.localOnly
        : SyncDirection.bidirectional;
    _syncTrigger = task?.syncTrigger ?? SyncTrigger.manual;
    _scheduleType = task?.scheduleType ?? ScheduleType.hours;
    _conflictStrategy = task?.conflictStrategy ?? ConflictStrategy.keepBoth;
    _isEnabled = task?.isEnabled ?? true;
    _selectedTargetId = task?.targetId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final targetProvider = context.read<TargetProvider>();
      await targetProvider.loadTargets();
      if (!mounted) return;
      _tryResolveLegacyTarget();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _localPathCtrl.dispose();
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
    const steps = ['基本信息', '同步目标', '同步规则', '定时策略'];

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
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
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
                  _buildTargetStep(),
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
              width: 120,
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
                        : Colors.grey[60],
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
          label: '同步模式',
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey[20],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _syncDirection == SyncDirection.localOnly
                        ? '仅本地模式：只做本地版本管理，不连接远端。'
                        : '双向模式（默认）：按 Git 风格在本地与目标间双向同步并记录历史。',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ToggleSwitch(
                  checked: _syncDirection == SyncDirection.localOnly,
                  onChanged: (value) {
                    setState(() {
                      _syncDirection = value
                          ? SyncDirection.localOnly
                          : SyncDirection.bidirectional;
                    });
                  },
                  content: const Text('仅本地'),
                ),
              ],
            ),
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

  Widget _buildTargetStep() {
    if (_syncDirection == SyncDirection.localOnly) {
      return _buildLocalOnlyHint();
    }

    return Consumer<TargetProvider>(
      builder: (context, targetProvider, _) {
        final targets = targetProvider.targets;
        final safeSelectedTargetId =
            targets.any((t) => t.id == _selectedTargetId)
            ? _selectedTargetId
            : null;
        final selected = targetProvider.getTarget(_selectedTargetId);
        final selectedStatus = _selectedTargetId == null
            ? const TargetStatusInfo()
            : targetProvider.statusOf(_selectedTargetId!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '先选择已配置的远端连接目标，再为当前任务单独配置目标路径。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '同步目标',
              child: SafeComboBox<String>(
                value: safeSelectedTargetId,
                isExpanded: true,
                placeholder: const Text('请选择一个目标'),
                emptyPlaceholder: '暂无可选目标，请先点击“新建目标”',
                items: targets
                    .map(
                      (t) => ComboBoxItem<String>(
                        value: t.id,
                        child: Text(
                          '${t.name} (${t.remoteHost}:${t.remotePort})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  setState(() => _selectedTargetId = id);
                },
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '任务目标路径',
              child: TextFormBox(
                controller: _remotePathCtrl,
                placeholder: '/shared/folder',
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? '请输入任务目标路径'
                    : null,
              ),
            ),
            if (selected?.remoteProtocol == RemoteProtocol.smb) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Button(
                    onPressed: () => _pickSmbRemotePath(selected!),
                    child: const Text('从 Windows 选择'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '建议从网络位置选择，自动转换为 /share/folder 格式。',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            FluentTheme.of(context).brightness ==
                                Brightness.dark
                            ? Colors.grey[100]
                            : Colors.grey[140],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  child: const Text('新建目标'),
                  onPressed: _createTarget,
                ),
                Button(
                  child: const Text('编辑所选'),
                  onPressed: selected == null
                      ? null
                      : () => _editTarget(selected),
                ),
                Button(
                  child: const Text('检测在线状态'),
                  onPressed: _selectedTargetId == null
                      ? null
                      : () => targetProvider.refreshTargetStatus(
                          _selectedTargetId!,
                        ),
                ),
                Button(
                  child: const Text('刷新目标列表'),
                  onPressed: () => targetProvider.loadTargets(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (selected == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('当前任务尚未选择目标，同步时将无法连接远端。'),
              )
            else
              _buildSelectedTargetCard(selected, selectedStatus),
          ],
        );
      },
    );
  }

  Widget _buildLocalOnlyHint() {
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
              '仅本地模式无需配置远端目标，此步骤将自动跳过。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTargetCard(SyncTarget target, TargetStatusInfo status) {
    final normalizedRemotePath = context
        .read<TargetProvider>()
        .normalizeTaskRemotePath(_remotePathCtrl.text);
    final (label, color) = switch (status.state) {
      TargetOnlineState.online => ('在线', AppStyles.successColor),
      TargetOnlineState.offline => ('离线', AppStyles.errorColor),
      TargetOnlineState.checking => ('检测中', AppStyles.warningColor),
      TargetOnlineState.unknown => ('未知', AppStyles.infoColor),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey[20],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                target.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${target.remoteProtocol.label}://'
            '${target.remoteHost}:${target.remotePort}',
          ),
          const SizedBox(height: 4),
          Text('任务目标路径: $normalizedRemotePath'),
          if (status.message != null) ...[
            const SizedBox(height: 4),
            Text(
              status.message!,
              style: TextStyle(
                fontSize: 12,
                color: FluentTheme.of(context).brightness == Brightness.dark
                    ? Colors.grey[100]
                    : Colors.grey[140],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncRulesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: '冲突处理策略',
          child: SafeComboBox<ConflictStrategy>(
            value: _conflictStrategy,
            items: ConflictStrategy.values
                .map((s) => ComboBoxItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _conflictStrategy = v);
            },
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
          child: SafeComboBox<SyncTrigger>(
            value: _syncTrigger,
            items: SyncTrigger.values
                .map((t) => ComboBoxItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _syncTrigger = v);
            },
          ),
        ),
        if (_syncTrigger == SyncTrigger.scheduled) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InfoLabel(
                  label: '定时周期',
                  child: SafeComboBox<ScheduleType>(
                    value: _scheduleType,
                    items: ScheduleType.values
                        .map(
                          (t) => ComboBoxItem(value: t, child: Text(t.label)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _scheduleType = v);
                    },
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
    if (result != null) {
      _localPathCtrl.text = result;
    }
  }

  Future<void> _pickSmbRemotePath(SyncTarget target) async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 SMB 远端目录',
      lockParentWindow: true,
    );

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }

    String convertedPath;
    try {
      convertedPath = context
          .read<TargetProvider>()
          .convertWindowsSelectedPathToSmbTaskRemotePath(
            selectedPath: selectedPath,
            target: target,
          );
    } catch (e) {
      if (!mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('无法使用该路径'),
          content: Text(e.toString()),
          severity: InfoBarSeverity.warning,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _remotePathCtrl.text = convertedPath);
  }

  SyncTask _buildTaskFromForm() {
    final targetProvider = context.read<TargetProvider>();
    final selectedTarget = targetProvider.getTarget(_selectedTargetId);

    return SyncTask(
      id: widget.task?.id,
      name: _nameCtrl.text,
      localPath: _localPathCtrl.text,
      targetId: _syncDirection == SyncDirection.localOnly
          ? null
          : _selectedTargetId,
      remoteProtocol:
          selectedTarget?.remoteProtocol ??
          widget.task?.remoteProtocol ??
          RemoteProtocol.webdav,
      remoteHost: selectedTarget?.remoteHost ?? widget.task?.remoteHost ?? '',
      remotePort: selectedTarget?.remotePort ?? widget.task?.remotePort ?? 443,
      remoteUsername:
          selectedTarget?.remoteUsername ?? widget.task?.remoteUsername ?? '',
      remotePassword:
          selectedTarget?.remotePassword ?? widget.task?.remotePassword ?? '',
      remotePath: targetProvider.normalizeTaskRemotePath(_remotePathCtrl.text),
      syncDirection: _syncDirection == SyncDirection.localOnly
          ? SyncDirection.localOnly
          : SyncDirection.bidirectional,
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
    if (_syncDirection != SyncDirection.localOnly &&
        _selectedTargetId == null) {
      displayInfoBar(
        context,
        builder: (context, close) => const InfoBar(
          title: Text('请先选择同步目标'),
          content: Text('非仅本地任务必须绑定一个已配置的远端目标。'),
          severity: InfoBarSeverity.warning,
        ),
      );
      setState(() => _currentStep = 1);
      return;
    }

    final targetProvider = context.read<TargetProvider>();
    final selectedTarget = targetProvider.getTarget(_selectedTargetId);
    final pathValidationError = targetProvider.validateTaskRemotePath(
      target: selectedTarget,
      remotePath: _remotePathCtrl.text,
    );
    if (_syncDirection != SyncDirection.localOnly &&
        pathValidationError != null) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('目标路径格式错误'),
          content: Text(pathValidationError),
          severity: InfoBarSeverity.error,
        ),
      );
      setState(() => _currentStep = 1);
      return;
    }

    final task = _buildTaskFromForm();
    final provider = context.read<TaskProvider>();

    bool success;
    if (isEditing) {
      success = await provider.updateTask(task);
    } else {
      final result = await provider.addTask(task);
      success = result != null;
    }

    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _createTarget() async {
    await showTargetEditDialog(context);
    if (!mounted) return;
    await context.read<TargetProvider>().loadTargets();
  }

  Future<void> _editTarget(SyncTarget target) async {
    await showTargetEditDialog(context, target: target);
    if (!mounted) return;
    await context.read<TargetProvider>().loadTargets();
  }

  void _tryResolveLegacyTarget() {
    if (_selectedTargetId != null || widget.task == null) {
      return;
    }

    final task = widget.task!;
    if (task.syncDirection == SyncDirection.localOnly) {
      return;
    }

    final targets = context.read<TargetProvider>().targets;
    for (final target in targets) {
      final matched =
          target.remoteProtocol == task.remoteProtocol &&
          target.remoteHost == task.remoteHost &&
          target.remotePort == task.remotePort &&
          target.remoteUsername == task.remoteUsername &&
          target.remotePassword == task.remotePassword;
      if (matched) {
        setState(() => _selectedTargetId = target.id);
        return;
      }
    }
  }
}
