import 'package:fluent_ui/fluent_ui.dart' hide ComboBoxItem;
import '../../core/constants/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/remote_connection.dart';
import '../../data/services/remote_connection_manager.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/safe_combo_box.dart';
import '../../l10n/l10n.dart';

class RemoteConnectionsPage extends StatefulWidget {
  const RemoteConnectionsPage({super.key});

  @override
  State<RemoteConnectionsPage> createState() => _RemoteConnectionsPageState();
}

class _RemoteConnectionsPageState extends State<RemoteConnectionsPage> {
  List<RemoteConnection> _connections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    setState(() => _isLoading = true);
    try {
      final connections = await RemoteConnectionManager.instance
          .listConnections();
      setState(() {
        _connections = connections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(context.l10n.remoteConnectionsPageTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(context.l10n.newConnection),
              onPressed: () => _showAddEditDialog(),
            ),
          ],
        ),
      ),
      content: _isLoading
          ? const Center(child: ProgressRing())
          : _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.server,
                    size: 64,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.noRemoteConnectionsConfigured,
                    style: AppStyles.textStyleSubtitle.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    child: Text(context.l10n.addConnection),
                    onPressed: () => _showAddEditDialog(),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _connections.length,
              itemBuilder: (context, index) {
                final conn = _connections[index];
                return _ConnectionCard(
                  connection: conn,
                  onTest: () => _testConnection(conn),
                  onEdit: () => _showAddEditDialog(connection: conn),
                  onDelete: () => _deleteConnection(conn),
                );
              },
            ),
    );
  }

  Future<void> _showAddEditDialog({RemoteConnection? connection}) async {
    await showDialog(
      context: context,
      builder: (context) => _AddEditConnectionDialog(
        connection: connection,
        onSaved: _loadConnections,
      ),
    );
  }

  Future<void> _testConnection(RemoteConnection conn) async {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(context.l10n.testingConnection),
        content: const Center(heightFactor: 2, child: ProgressRing()),
      ),
      barrierDismissible: false,
    );

    try {
      final result = await RemoteConnectionManager.instance
          .testConnectionDirect(conn);
      Navigator.pop(context);

      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(
            result.success
                ? context.l10n.connectionSuccessful
                : context.l10n.connectionFailed,
          ),
          content: Text(
            result.success
                ? context.l10n.successfullyConnectedTo(conn.displayAddress)
                : result.error ?? context.l10n.unknownError,
          ),
          actions: [
            Button(
              child: Text(context.l10n.ok),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(context.l10n.error),
          content: Text(e.toString()),
          actions: [
            Button(
              child: Text(context.l10n.ok),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteConnection(RemoteConnection conn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(context.l10n.deleteConnection),
        content: Text(context.l10n.deleteConnectionConfirm(conn.name)),
        actions: [
          Button(
            child: Text(context.l10n.cancel),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: Text(context.l10n.delete),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await RemoteConnectionManager.instance.removeConnection(conn.id);
      _loadConnections();
    }
  }
}

class _ConnectionCard extends StatelessWidget {
  final RemoteConnection connection;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return AppCardSurface(
      child: Row(
        children: [
          Icon(
            connection.protocol.value == 'smb'
                ? FluentIcons.server
                : connection.protocol.value == 'unc'
                ? FluentIcons.folder
                : FluentIcons.cloud,
            size: 32,
            color: isDark ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.name,
                  style: AppStyles.textStyleSubtitle.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  connection.displayAddress,
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.lightTextSecondary(isDark),
                  ),
                ),
                if (connection.username.isNotEmpty &&
                    connection.protocol != RemoteProtocol.unc)
                  Text(
                    '${context.l10n.user}: ${connection.username}',
                    style: AppStyles.textStyleCaption.copyWith(
                      color: AppStyles.lightTextSecondary(isDark),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Button(child: Text(context.l10n.test), onPressed: onTest),
              const SizedBox(width: 8),
              Button(child: Text(context.l10n.edit), onPressed: onEdit),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(FluentIcons.delete, color: Colors.red),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddEditConnectionDialog extends StatefulWidget {
  final RemoteConnection? connection;
  final VoidCallback onSaved;

  const _AddEditConnectionDialog({this.connection, required this.onSaved});

  @override
  State<_AddEditConnectionDialog> createState() =>
      _AddEditConnectionDialogState();
}

class _AddEditConnectionDialogState extends State<_AddEditConnectionDialog> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  RemoteProtocol _protocol = RemoteProtocol.smb;
  bool _isLoading = false;
  bool _obscurePassword = true;

  bool get _isEditing => widget.connection != null;

  /// 是否需要显示端口字段（UNC 不需要端口）
  bool get _showPortField => _protocol.requiresPort;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      _nameController.text = widget.connection!.name;
      _hostController.text = widget.connection!.host;
      _portController.text = widget.connection!.port.toString();
      _usernameController.text = widget.connection!.username;
      _passwordController.text = widget.connection!.password;
      _protocol = widget.connection!.protocol;
    } else {
      _portController.text = '445';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(
        _isEditing
            ? context.l10n.editConnection
            : context.l10n.newConnectionDialog,
      ),
      constraints: const BoxConstraints(maxWidth: 450),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLabel(
              label: context.l10n.name,
              child: TextBox(
                controller: _nameController,
                placeholder: context.l10n.nameExample,
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: context.l10n.protocol,
              child: SafeComboBox<RemoteProtocol>(
                value: _protocol,
                isExpanded: true,
                items: [
                  ComboBoxItem(
                    value: RemoteProtocol.smb,
                    child: Text(context.l10n.smb),
                  ),
                  ComboBoxItem(
                    value: RemoteProtocol.webdav,
                    child: Text(context.l10n.webdav),
                  ),
                  ComboBoxItem(
                    value: RemoteProtocol.unc,
                    child: Text(context.l10n.windowsUnc),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _protocol = v;
                      // UNC 不需要端口
                      if (v == RemoteProtocol.unc) {
                        _portController.text = '0';
                      } else if (v == RemoteProtocol.smb) {
                        _portController.text = '445';
                      } else {
                        _portController.text = '443';
                      }
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: _protocol == RemoteProtocol.unc
                  ? context.l10n.uncPath
                  : context.l10n.host,
              child: TextBox(
                controller: _hostController,
                placeholder: _protocol == RemoteProtocol.unc
                    ? context.l10n.uncPathExample
                    : context.l10n.hostExample,
              ),
            ),
            if (_showPortField) ...[
              const SizedBox(height: 12),
              InfoLabel(
                label: context.l10n.port,
                child: TextBox(
                  controller: _portController,
                  placeholder: _protocol == RemoteProtocol.smb ? '445' : '443',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
            if (_protocol != RemoteProtocol.unc) ...[
              const SizedBox(height: 12),
              InfoLabel(
                label: context.l10n.username,
                child: TextBox(
                  controller: _usernameController,
                  placeholder: context.l10n.usernameExample,
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: context.l10n.password,
                child: PasswordBox(
                  controller: _passwordController,
                  revealMode: _obscurePassword
                      ? PasswordRevealMode.hidden
                      : PasswordRevealMode.visible,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          child: Text(context.l10n.cancel),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(_isEditing ? context.l10n.save : context.l10n.create),
          onPressed: _isLoading ? null : _save,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text) ?? 445;

    if (name.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(context.l10n.validationError),
          content: Text(context.l10n.nameRequired),
          actions: [
            Button(
              child: Text(context.l10n.ok),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    if (host.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(context.l10n.validationError),
          content: Text(context.l10n.hostRequired),
          actions: [
            Button(
              child: Text(context.l10n.ok),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final connection = RemoteConnection(
        id: widget.connection?.id,
        name: name,
        protocol: _protocol,
        host: host,
        port: port,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (_isEditing) {
        await RemoteConnectionManager.instance.updateConnection(connection);
      } else {
        await RemoteConnectionManager.instance.addConnection(connection);
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(context.l10n.error),
            content: Text(e.toString()),
            actions: [
              Button(
                child: Text(context.l10n.ok),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
