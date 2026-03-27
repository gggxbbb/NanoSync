import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants/enums.dart';
import '../../data/models/remote_connection.dart';
import '../../data/services/remote_connection_manager.dart';

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
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Remote Connections'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('New Connection'),
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
                  const Icon(FluentIcons.server, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No remote connections configured',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    child: const Text('Add Connection'),
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
        title: const Text('Testing Connection'),
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
            result.success ? 'Connection Successful' : 'Connection Failed',
          ),
          content: Text(
            result.success
                ? 'Successfully connected to ${conn.displayAddress}'
                : result.error ?? 'Unknown error',
          ),
          actions: [
            Button(
              child: const Text('OK'),
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
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [
            Button(
              child: const Text('OK'),
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
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete "${conn.name}"?'),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('Delete'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              connection.protocol.value == 'smb'
                  ? FluentIcons.server
                  : FluentIcons.cloud,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.name,
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  Text(
                    connection.displayAddress,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  if (connection.username.isNotEmpty)
                    Text(
                      'User: ${connection.username}',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Button(child: const Text('Test'), onPressed: onTest),
                const SizedBox(width: 8),
                Button(child: const Text('Edit'), onPressed: onEdit),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(FluentIcons.delete, color: Colors.red),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
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
      title: Text(_isEditing ? 'Edit Connection' : 'New Connection'),
      constraints: const BoxConstraints(maxWidth: 450),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLabel(
              label: 'Name',
              child: TextBox(
                controller: _nameController,
                placeholder: 'e.g., nas-backup',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Protocol',
              child: ComboBox<RemoteProtocol>(
                value: _protocol,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: RemoteProtocol.smb, child: Text('SMB')),
                  ComboBoxItem(
                    value: RemoteProtocol.webdav,
                    child: Text('WebDAV'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _protocol = v;
                      _portController.text = v == RemoteProtocol.smb
                          ? '445'
                          : '443';
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Host',
              child: TextBox(
                controller: _hostController,
                placeholder: 'e.g., 192.168.1.100',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Port',
              child: TextBox(
                controller: _portController,
                placeholder: _protocol == RemoteProtocol.smb ? '445' : '443',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Username (optional)',
              child: TextBox(
                controller: _usernameController,
                placeholder: 'Leave empty for guest access',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Password (optional)',
              child: PasswordBox(
                controller: _passwordController,
                revealMode: _obscurePassword
                    ? PasswordRevealMode.hidden
                    : PasswordRevealMode.visible,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Save' : 'Create'),
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
          title: const Text('Validation Error'),
          content: const Text('Name is required'),
          actions: [
            Button(
              child: const Text('OK'),
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
          title: const Text('Validation Error'),
          content: const Text('Host is required'),
          actions: [
            Button(
              child: const Text('OK'),
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
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              Button(
                child: const Text('OK'),
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
