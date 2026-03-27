import 'package:fluent_ui/fluent_ui.dart';
import '../../data/models/remote_connection.dart';
import '../../data/services/new_sync_engine.dart';
import '../../data/services/repository_manager.dart';
import '../../data/services/remote_connection_manager.dart';
import '../../l10n/l10n.dart';

class RepositoryListPage extends StatefulWidget {
  const RepositoryListPage({super.key});

  @override
  State<RepositoryListPage> createState() => _RepositoryListPageState();
}

class _RepositoryListPageState extends State<RepositoryListPage> {
  List<Repository> _repositories = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRepositories();
  }

  Future<void> _loadRepositories() async {
    setState(() => _isLoading = true);
    try {
      final repos = await RepositoryManager.instance.listRepositories();
      setState(() {
        _repositories = repos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(context.l10n.error),
            content: Text('${context.l10n.error}: $e'),
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
  }

  List<Repository> get _filteredRepositories {
    if (_searchQuery.isEmpty) return _repositories;
    return _repositories.where((r) {
      final nameLower = r.name.toLowerCase();
      final pathLower = r.localPath.toLowerCase();
      final queryLower = _searchQuery.toLowerCase();
      return nameLower.contains(queryLower) || pathLower.contains(queryLower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: Text(context.l10n.repositoriesPageTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(context.l10n.addRepository),
              onPressed: () => _showAddRepositoryDialog(),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.cloud_download),
              label: Text(context.l10n.clone),
              onPressed: () => _showCloneDialog(),
            ),
          ],
        ),
      ),
      content: _isLoading
          ? const Center(child: ProgressRing())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextBox(
                    placeholder: context.l10n.searchRepositories,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(FluentIcons.search),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Expanded(
                  child: _filteredRepositories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(FluentIcons.folder_open, size: 64),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? context.l10n.noRepositoriesRegistered
                                    : context.l10n.noRepositoriesMatch,
                                style: FluentTheme.of(
                                  context,
                                ).typography.subtitle,
                              ),
                              const SizedBox(height: 8),
                              if (_searchQuery.isEmpty)
                                FilledButton(
                                child: Text(context.l10n.addRepository),
                                  onPressed: () => _showAddRepositoryDialog(),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredRepositories.length,
                          itemBuilder: (context, index) {
                            final repo = _filteredRepositories[index];
                            return _RepositoryCard(
                              repository: repo,
                              onRefresh: _loadRepositories,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAddRepositoryDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _AddRepositoryDialog(onCreated: _loadRepositories),
    );
  }

  Future<void> _showCloneDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _CloneRepositoryDialog(onCloned: _loadRepositories),
    );
  }
}

class _RepositoryCard extends StatefulWidget {
  final Repository repository;
  final VoidCallback onRefresh;

  const _RepositoryCard({required this.repository, required this.onRefresh});

  @override
  State<_RepositoryCard> createState() => _RepositoryCardState();
}

class _RepositoryCardState extends State<_RepositoryCard> {
  int _ahead = 0;
  int _behind = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final result = await NewSyncEngine.instance.fetch(widget.repository);
      if (mounted) {
        setState(() {
          _ahead = result.ahead;
          _behind = result.behind;
        });
      }
    } catch (_) {}
  }

  Future<void> _sync() async {
    setState(() => _isLoading = true);
    try {
      await NewSyncEngine.instance.sync(widget.repository);
      await _loadStatus();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(FluentIcons.folder, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.repository.name,
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  Text(
                    widget.repository.localPath,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  if (_ahead > 0 || _behind > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          if (_ahead > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Tooltip(
                                message: context.l10n.commitsAhead(_ahead),
                                child: Row(
                                  children: [
                                    const Icon(FluentIcons.upload, size: 14),
                                    const SizedBox(width: 4),
                                    Text('$_ahead'),
                                  ],
                                ),
                              ),
                            ),
                          if (_behind > 0)
                            Tooltip(
                              message: context.l10n.commitsBehind(_behind),
                              child: Row(
                                children: [
                                  const Icon(FluentIcons.download, size: 14),
                                  const SizedBox(width: 4),
                                  Text('$_behind'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_isLoading)
              const ProgressRing()
            else
              Row(
                children: [
                  Button(
                    child: Text(context.l10n.fetch),
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await _loadStatus();
                      } finally {
                        if (mounted) {
                          setState(() => _isLoading = false);
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton(child: Text(context.l10n.sync), onPressed: _sync),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AddRepositoryDialog extends StatefulWidget {
  final VoidCallback onCreated;

  const _AddRepositoryDialog({required this.onCreated});

  @override
  State<_AddRepositoryDialog> createState() => _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends State<_AddRepositoryDialog> {
  final _pathController = TextEditingController();
  final _nameController = TextEditingController();
  bool _initialCommit = true;
  String? _selectedConnection;
  final _remotePathController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(context.l10n.addRepositoryDialogTitle),
      constraints: const BoxConstraints(maxWidth: 500),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLabel(
              label: context.l10n.localPath,
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _pathController,
                      placeholder: context.l10n.selectFolder,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    child: const Text('Browse'),
                    onPressed: () async {
                      // TODO: Implement folder picker
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: context.l10n.repositoryName,
              child: TextBox(
                controller: _nameController,
                placeholder: context.l10n.enterName,
              ),
            ),
            const SizedBox(height: 12),
            Checkbox(
              checked: _initialCommit,
              onChanged: (v) => setState(() => _initialCommit = v ?? true),
              content: Text(context.l10n.createInitialCommit),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.remoteConfiguration,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<RemoteConnection>>(
              future: RemoteConnectionManager.instance.listConnections(),
              builder: (context, snapshot) {
                final connections = snapshot.data ?? [];
                return InfoLabel(
                  label: context.l10n.connection,
                  child: ComboBox<String?>(
                    value: _selectedConnection,
                    isExpanded: true,
                    placeholder: Text(context.l10n.selectConnection),
                    items: connections
                        .map(
                          (c) => ComboBoxItem(
                            value: c.name,
                            child: Text('${c.name} (${c.displayAddress})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedConnection = v),
                  ),
                );
              },
            ),
            if (_selectedConnection != null) ...[
              const SizedBox(height: 12),
              InfoLabel(
                label: context.l10n.remotePath,
                child: TextBox(
                  controller: _remotePathController,
                  placeholder: context.l10n.remotePathPlaceholder,
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
              : Text(context.l10n.create),
          onPressed: _isLoading
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  try {
                    await RepositoryManager.instance.importExisting(
                      _pathController.text,
                      name: _nameController.text.isEmpty
                          ? null
                          : _nameController.text,
                      initialCommit: _initialCommit,
                      remoteName: _selectedConnection,
                      remotePath: _remotePathController.text.isEmpty
                          ? null
                          : _remotePathController.text,
                    );
                    widget.onCreated();
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      await showDialog(
                        context: context,
                        builder: (context) => ContentDialog(
                          title: Text(context.l10n.error),
                          content: Text('${context.l10n.error}: $e'),
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
                },
        ),
      ],
    );
  }
}

class _CloneRepositoryDialog extends StatefulWidget {
  final VoidCallback onCloned;

  const _CloneRepositoryDialog({required this.onCloned});

  @override
  State<_CloneRepositoryDialog> createState() => _CloneRepositoryDialogState();
}

class _CloneRepositoryDialogState extends State<_CloneRepositoryDialog> {
  String? _selectedConnection;
  final _remotePathController = TextEditingController();
  final _localPathController = TextEditingController();
  double _progress = 0;
  String _status = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('Clone Repository'),
      constraints: const BoxConstraints(maxWidth: 500),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<List<RemoteConnection>>(
              future: RemoteConnectionManager.instance.listConnections(),
              builder: (context, snapshot) {
                final connections = snapshot.data ?? [];
                return InfoLabel(
                  label: 'Remote Connection',
                  child: ComboBox<String?>(
                    value: _selectedConnection,
                    isExpanded: true,
                    placeholder: const Text('Select connection...'),
                    items: connections
                        .map(
                          (c) => ComboBoxItem(
                            value: c.name,
                            child: Text('${c.name} (${c.displayAddress})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedConnection = v),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Remote Path',
              child: TextBox(
                controller: _remotePathController,
                placeholder: '/path/to/repository',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Local Path',
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _localPathController,
                      placeholder: 'Select destination...',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    child: const Text('Browse'),
                    onPressed: () async {
                      // TODO: Implement folder picker
                    },
                  ),
                ],
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              ProgressBar(value: _progress * 100),
              const SizedBox(height: 8),
              Text(_status),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        FilledButton(
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('Clone'),
          onPressed: _selectedConnection == null || _isLoading
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  try {
                    await RepositoryManager.instance.clone(
                      connectionName: _selectedConnection!,
                      remotePath: _remotePathController.text,
                      localPath: _localPathController.text,
                      onProgress: (progress, message) {
                        setState(() {
                          _progress = progress;
                          _status = message;
                        });
                      },
                    );
                    widget.onCloned();
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      await showDialog(
                        context: context,
                        builder: (context) => ContentDialog(
                          title: const Text('Error'),
                          content: Text('Failed to clone repository: $e'),
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
                },
        ),
      ],
    );
  }
}
