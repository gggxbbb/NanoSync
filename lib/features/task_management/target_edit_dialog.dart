import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sync_target.dart';
import '../../shared/providers/target_provider.dart';
import '../../shared/widgets/components/safe_combo_box.dart';

Future<void> showTargetEditDialog(
  BuildContext context, {
  SyncTarget? target,
}) async {
  await showDialog(
    context: context,
    builder: (context) => _TargetEditDialog(target: target),
  );
}

class _TargetEditDialog extends StatefulWidget {
  const _TargetEditDialog({this.target});

  final SyncTarget? target;

  @override
  State<_TargetEditDialog> createState() => _TargetEditDialogState();
}

class _TargetEditDialogState extends State<_TargetEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _probePathCtrl;

  RemoteProtocol _protocol = RemoteProtocol.webdav;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.target != null;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    _nameCtrl = TextEditingController(text: target?.name ?? '');
    _hostCtrl = TextEditingController(text: target?.remoteHost ?? '');
    _portCtrl = TextEditingController(
      text: (target?.remotePort ?? 443).toString(),
    );
    _usernameCtrl = TextEditingController(text: target?.remoteUsername ?? '');
    _passwordCtrl = TextEditingController(text: target?.remotePassword ?? '');
    _probePathCtrl = TextEditingController(
      text: context.read<TargetProvider>().defaultWebDavProbePath,
    );
    _protocol = target?.remoteProtocol ?? RemoteProtocol.webdav;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _probePathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(_isEditing ? '编辑同步目标' : '新建同步目标'),
      constraints: const BoxConstraints(maxWidth: 520),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoLabel(
              label: '目标名称',
              child: TextFormBox(
                controller: _nameCtrl,
                placeholder: '例如：生产环境 WebDAV',
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入目标名称' : null,
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '协议',
              child: SafeComboBox<RemoteProtocol>(
                value: _protocol,
                items: RemoteProtocol.values
                    .map((e) => ComboBoxItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _protocol = value;
                    _portCtrl.text = value == RemoteProtocol.webdav
                        ? '443'
                        : '445';
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InfoLabel(
                    label: '服务器地址',
                    child: TextFormBox(
                      controller: _hostCtrl,
                      placeholder: '192.168.1.100',
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? '请输入服务器地址'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: '端口',
                    child: TextFormBox(
                      controller: _portCtrl,
                      placeholder: '443',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final port = int.tryParse(value ?? '');
                        if (port == null || port <= 0 || port > 65535) {
                          return '端口无效';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: '用户名',
                    child: TextFormBox(
                      controller: _usernameCtrl,
                      placeholder: '可留空（匿名）',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: '密码',
                    child: PasswordBox(
                      controller: _passwordCtrl,
                      placeholder: '可留空',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '连接探测路径（可选，仅测试用）',
              child: TextFormBox(
                controller: _probePathCtrl,
                placeholder: '/ （WebDAV 生效）',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(),
                        )
                      : const Text('测试连接'),
                ),
                const SizedBox(width: 10),
                if (_testResult != null)
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testResult!.contains('成功')
                            ? AppStyles.successColor
                            : AppStyles.errorColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(child: Text(_isEditing ? '保存' : '创建'), onPressed: _save),
      ],
    );
  }

  SyncTarget _buildTarget() {
    return SyncTarget(
      id: widget.target?.id,
      name: _nameCtrl.text.trim(),
      remoteProtocol: _protocol,
      remoteHost: _hostCtrl.text.trim(),
      remotePort: int.tryParse(_portCtrl.text.trim()) ?? 443,
      remoteUsername: _usernameCtrl.text.trim(),
      remotePassword: _passwordCtrl.text,
      createdAt: widget.target?.createdAt,
      updatedAt: widget.target?.updatedAt,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final provider = context.read<TargetProvider>();
    final target = _buildTarget();
    final status = await provider.checkTargetOnline(
      target,
      probePath: _probePathCtrl.text,
      strictCredentialCheck: true,
    );

    if (!mounted) return;

    setState(() {
      _testing = false;
      _testResult = status.state == TargetOnlineState.online
          ? '连接测试成功'
          : status.message ?? '连接失败';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<TargetProvider>();
    final target = _buildTarget();

    bool success;
    if (_isEditing) {
      success = await provider.updateTarget(target);
    } else {
      success = await provider.addTarget(target) != null;
    }

    if (!mounted) return;

    if (success) {
      await provider.refreshTargetStatus(target.id);
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('保存失败'),
        content: Text(provider.error ?? '无法保存同步目标'),
        severity: InfoBarSeverity.error,
      ),
    );
  }
}
