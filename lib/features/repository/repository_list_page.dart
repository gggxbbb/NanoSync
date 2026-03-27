import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide ComboBoxItem;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/remote_directory_item.dart';
import '../../data/models/remote_connection.dart';
import '../../data/models/repository_config.dart';
import '../../data/services/repository_local_settings_service.dart';
import '../../data/services/new_sync_engine.dart';
import '../../data/services/repository_manager.dart';
import '../../data/services/remote_connection_manager.dart';
import '../../data/services/storage_estimator_service.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/safe_combo_box.dart';
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
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(context.l10n.repositoriesPageTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(context.l10n.addRepository),
              onPressed: _showAddRepositoryDialog,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.cloud_download),
              label: Text(context.l10n.clone),
              onPressed: _showCloneDialog,
            ),
          ],
        ),
      ),
      content: _isLoading
          ? const Center(child: ProgressRing())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextBox(
                    placeholder: context.l10n.searchRepositories,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
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
                                style: AppStyles.textStyleSubtitle.copyWith(
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_searchQuery.isEmpty)
                                FilledButton(
                                  child: Text(context.l10n.addRepository),
                                  onPressed: _showAddRepositoryDialog,
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
  Map<String, dynamic>? _defaultRemote;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadDefaultRemote();
  }

  Future<void> _loadStatus() async {
    try {
      final result = await NewSyncEngine.instance.fetch(
        widget.repository,
        recordLog: false,
      );
      if (mounted) {
        setState(() {
          _ahead = result.ahead;
          _behind = result.behind;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDefaultRemote() async {
    try {
      final remote = await RemoteConnectionManager.instance
          .getDefaultRepositoryRemote(widget.repository.id);
      if (mounted) {
        setState(() => _defaultRemote = remote);
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

  Future<void> _showDeleteDialog() async {
    final result = await showDialog<_DeleteRepositoryResult>(
      context: context,
      builder: (context) =>
          _DeleteRepositoryDialog(repositoryName: widget.repository.name),
    );

    if (result != null && mounted) {
      setState(() => _isLoading = true);
      try {
        await RepositoryManager.instance.deleteRepository(
          widget.repository.id,
          deleteNanosyncFolder: result.deleteNanosyncFolder,
        );
        widget.onRefresh();
      } catch (e) {
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
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _showMigrateDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _MigrateRepositoryDialog(
        repository: widget.repository,
        onMigrated: widget.onRefresh,
      ),
    );
  }

  Future<void> _showRepositoryLocalSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (context) =>
          _RepositoryLocalSettingsDialog(repository: widget.repository),
    );
  }

  Future<void> _showAdjustRemoteDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _AdjustRepositoryRemoteDialog(
        repository: widget.repository,
        onSaved: () async {
          await _loadDefaultRemote();
          widget.onRefresh();
        },
      ),
    );

    if (updated == true) {
      await _loadDefaultRemote();
    }
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoBubble({
    required String text,
    required IconData icon,
    required Color color,
    String? tooltip,
  }) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppStyles.statusBadgeBackground(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppStyles.statusBadgeTextColor(color)),
          const SizedBox(width: 5),
          Text(
            text,
            style: AppStyles.textStyleCaption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppStyles.statusBadgeTextColor(color),
            ),
          ),
        ],
      ),
    );

    if (tooltip == null || tooltip.isEmpty) {
      return bubble;
    }
    return Tooltip(message: tooltip, child: bubble);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return AppCardSurface(
      child: Row(
        children: [
          Icon(
            FluentIcons.folder,
            size: 32,
            color: isDark ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.repository.name,
                  style: AppStyles.textStyleSubtitle.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  widget.repository.localPath,
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.lightTextSecondary(isDark),
                  ),
                ),
                if (_defaultRemote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          FluentIcons.plug_connected,
                          size: 14,
                          color: AppStyles.lightTextSecondary(isDark),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_defaultRemote!['remote_name']}  ${_defaultRemote!['remote_path']}',
                            style: AppStyles.textStyleCaption.copyWith(
                              color: AppStyles.lightTextSecondary(isDark),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_defaultRemote != null)
                        _buildInfoBubble(
                          text: '已绑定远端',
                          icon: FluentIcons.plug_connected,
                          color: AppStyles.successColor,
                        )
                      else
                        _buildInfoBubble(
                          text: '未绑定远端',
                          icon: FluentIcons.plug_disconnected,
                          color: AppStyles.warningColor,
                        ),
                      if (_ahead > 0)
                        _buildInfoBubble(
                          text: '待推送 $_ahead',
                          icon: FluentIcons.upload,
                          color: AppStyles.infoColor,
                          tooltip: context.l10n.commitsAhead(_ahead),
                        ),
                      if (_behind > 0)
                        _buildInfoBubble(
                          text: '待拉取 $_behind',
                          icon: FluentIcons.download,
                          color: AppStyles.infoColor,
                          tooltip: context.l10n.commitsBehind(_behind),
                        ),
                      if (_defaultRemote != null && _ahead == 0 && _behind == 0)
                        _buildInfoBubble(
                          text: '已同步',
                          icon: FluentIcons.check_mark,
                          color: AppStyles.successColor,
                        ),
                      if (widget.repository.lastAccessed != null)
                        _buildInfoBubble(
                          text:
                              '最近访问 ${_formatRelativeTime(widget.repository.lastAccessed!)}',
                          icon: FluentIcons.clock,
                          color: AppStyles.warningColor,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: context.l10n.goToVersionControl,
            child: IconButton(
              icon: Icon(
                FluentIcons.git_graph,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () {
                AppShell.navigateToPage(
                  context,
                  pageIndex: AppPageIndex.versionControl,
                  repositoryId: widget.repository.id,
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: context.l10n.goToAutomation,
            child: IconButton(
              icon: Icon(
                FluentIcons.settings,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () {
                AppShell.navigateToPage(
                  context,
                  pageIndex: AppPageIndex.automation,
                  repositoryId: widget.repository.id,
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '${context.l10n.edit}${context.l10n.remoteConfiguration}',
            child: IconButton(
              icon: Icon(
                FluentIcons.cloud,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _showAdjustRemoteDialog,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '版本保留设置',
            child: IconButton(
              icon: Icon(
                FluentIcons.history,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _showRepositoryLocalSettingsDialog,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: context.l10n.migrateRepository,
            child: IconButton(
              icon: Icon(
                FluentIcons.move_to_folder,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _showMigrateDialog,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: context.l10n.deleteRepository,
            child: IconButton(
              icon: Icon(FluentIcons.delete, size: 18, color: Colors.red),
              onPressed: _showDeleteDialog,
            ),
          ),
          const SizedBox(width: 8),
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
    );
  }
}

class _AdjustRepositoryRemoteDialog extends StatefulWidget {
  final Repository repository;
  final Future<void> Function() onSaved;

  const _AdjustRepositoryRemoteDialog({
    required this.repository,
    required this.onSaved,
  });

  @override
  State<_AdjustRepositoryRemoteDialog> createState() =>
      _AdjustRepositoryRemoteDialogState();
}

class _AdjustRepositoryRemoteDialogState
    extends State<_AdjustRepositoryRemoteDialog> {
  final _remotePathController = TextEditingController();
  List<RemoteConnection> _connections = [];
  String? _selectedConnection;
  bool _isLoading = true;
  bool _isSaving = false;

  RemoteConnection? get _selectedConnectionModel {
    final name = _selectedConnection;
    if (name == null) return null;
    for (final c in _connections) {
      if (c.name == name) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _remotePathController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        RemoteConnectionManager.instance.listConnections(),
        RemoteConnectionManager.instance.getDefaultRepositoryRemote(
          widget.repository.id,
        ),
      ]);

      final connections = results[0] as List<RemoteConnection>;
      final defaultRemote = results[1] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _connections = connections;
        _selectedConnection = defaultRemote?['remote_name'] as String?;
        _remotePathController.text =
            (defaultRemote?['remote_path'] as String?) ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final connectionName = _selectedConnection;
    final remotePath = _remotePathController.text.trim();
    if (connectionName == null || remotePath.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(context.l10n.error),
          content: Text(context.l10n.selectConnection),
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

    setState(() => _isSaving = true);
    try {
      await RemoteConnectionManager.instance.bindToRepository(
        repositoryId: widget.repository.id,
        connectionName: connectionName,
        remotePath: remotePath,
        isDefault: true,
      );
      await RemoteConnectionManager.instance.setDefaultRemote(
        repositoryId: widget.repository.id,
        connectionName: connectionName,
      );
      await widget.onSaved();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _chooseRemotePath() async {
    final connection = _selectedConnectionModel;
    if (connection == null) {
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _RemotePathPickerDialog(
        connectionName: connection.name,
        initialPath: _remotePathController.text.trim().isEmpty
            ? '/'
            : _remotePathController.text.trim(),
      ),
    );

    if (!mounted || selected == null) {
      return;
    }
    setState(() => _remotePathController.text = selected);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text('${context.l10n.edit}${context.l10n.remoteConfiguration}'),
      constraints: const BoxConstraints(maxWidth: 500),
      content: _isLoading
          ? const SizedBox(height: 120, child: Center(child: ProgressRing()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.repository.name,
                  style: AppStyles.textStyleSubtitle,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.repository.localPath,
                  style: AppStyles.textStyleCaption,
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: context.l10n.connection,
                  child: SafeComboBox<String>(
                    value: _selectedConnection,
                    isExpanded: true,
                    placeholder: Text(context.l10n.selectConnection),
                    emptyPlaceholder:
                        context.l10n.noRemoteConnectionsConfigured,
                    items: _connections
                        .map(
                          (c) => ComboBoxItem(
                            value: c.name,
                            child: Text('${c.name} (${c.displayAddress})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedConnection = v),
                  ),
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: context.l10n.remotePath,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextBox(
                          controller: _remotePathController,
                          placeholder: context.l10n.remotePathPlaceholder,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: _selectedConnectionModel == null
                            ? null
                            : _chooseRemotePath,
                        child: const Text('可视化选择'),
                      ),
                    ],
                  ),
                ),
                if (_selectedConnectionModel != null &&
                    !RemoteConnectionManager.instance.supportsRemotePathBrowser(
                      _selectedConnectionModel!,
                    ))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '当前协议暂不支持可视化目录浏览，请手动填写路径。',
                      style: AppStyles.textStyleCaption,
                    ),
                  ),
              ],
            ),
      actions: [
        Button(
          child: Text(context.l10n.cancel),
          onPressed: _isSaving ? null : () => Navigator.pop(context),
        ),
        FilledButton(
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(context.l10n.save),
          onPressed: _isSaving || _isLoading ? null : _save,
        ),
      ],
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
  String? _selectedConnection;
  final _remotePathController = TextEditingController();
  bool _isLoading = false;
  bool _isEstimating = false;
  int? _estimatedExtraBytes;
  int _maxVersions = AppConstants.defaultMaxVersions;
  int _maxVersionDays = AppConstants.defaultMaxVersionDays;
  int _maxVersionSizeGB = AppConstants.defaultMaxVersionSizeGB;

  // 忽略配置
  final _ignorePatternsController = TextEditingController();
  final _ignoreExtensionsController = TextEditingController();
  final _ignoreFoldersController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    _remotePathController.dispose();
    _ignorePatternsController.dispose();
    _ignoreExtensionsController.dispose();
    _ignoreFoldersController.dispose();
    super.dispose();
  }

  Future<void> _recalculateEstimate() async {
    final path = _pathController.text.trim();
    if (path.isEmpty || !await Directory(path).exists()) {
      if (!mounted) return;
      setState(() {
        _estimatedExtraBytes = null;
        _isEstimating = false;
      });
      return;
    }

    setState(() => _isEstimating = true);
    try {
      final estimate = await StorageEstimatorService.instance
          .estimateRetentionOverhead(
            rootPath: path,
            maxVersions: _maxVersions,
            maxDays: _maxVersionDays,
            maxSizeGB: _maxVersionSizeGB,
          );
      if (!mounted) return;
      setState(() {
        _estimatedExtraBytes = estimate.estimatedExtraBytes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _estimatedExtraBytes = null);
    } finally {
      if (mounted) {
        setState(() => _isEstimating = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(value >= 100
        ? 0
        : value >= 10
        ? 1
        : 2)} ${units[index]}';
  }

  Future<void> _chooseRemotePath() async {
    final selectedConnection = _selectedConnection;
    if (selectedConnection == null) {
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _RemotePathPickerDialog(
        connectionName: selectedConnection,
        initialPath: _remotePathController.text.trim().isEmpty
            ? '/'
            : _remotePathController.text.trim(),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _remotePathController.text = selected);
  }

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
                    child: Text(context.l10n.browse),
                    onPressed: () async {
                      final result = await FilePicker.platform
                          .getDirectoryPath();
                      if (result != null) {
                        _pathController.text = result;
                        // 自动填充仓库名称
                        if (_nameController.text.isEmpty) {
                          final name = result.split(RegExp(r'[/\\]')).last;
                          _nameController.text = name;
                        }
                        await _recalculateEstimate();
                      }
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
            const SizedBox(height: 16),
            Text(
              context.l10n.ignoreConfiguration,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InfoLabel(
              label: context.l10n.ignorePatterns,
              child: TextBox(
                controller: _ignorePatternsController,
                placeholder:
                    '${context.l10n.ignorePatternsPlaceholder} (支持 re:正则 或 /regex/)',
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            InfoLabel(
              label: context.l10n.ignoreExtensions,
              child: TextBox(
                controller: _ignoreExtensionsController,
                placeholder: context.l10n.ignoreExtensionsPlaceholder,
              ),
            ),
            const SizedBox(height: 8),
            InfoLabel(
              label: context.l10n.ignoreFolders,
              child: TextBox(
                controller: _ignoreFoldersController,
                placeholder: context.l10n.ignoreFoldersPlaceholder,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '版本保留配置（仅本机）',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: '保留版本数',
                    child: NumberBox(
                      value: _maxVersions.toDouble(),
                      min: 1,
                      max: 500,
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _maxVersions = value.toInt());
                        await _recalculateEstimate();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoLabel(
                    label: '保留天数',
                    child: NumberBox(
                      value: _maxVersionDays.toDouble(),
                      min: 1,
                      max: 3650,
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _maxVersionDays = value.toInt());
                        await _recalculateEstimate();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoLabel(
                    label: '容量上限(GB)',
                    child: NumberBox(
                      value: _maxVersionSizeGB.toDouble(),
                      min: 1,
                      max: 10000,
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _maxVersionSizeGB = value.toInt());
                        await _recalculateEstimate();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isEstimating)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在估算额外存储占用...'),
                ],
              )
            else
              Text(
                _estimatedExtraBytes == null
                    ? '选择本地路径后将显示预计额外占用空间。'
                    : '预计额外占用: ${_formatBytes(_estimatedExtraBytes!)}（基于仓库结构的动态估算）',
                style: AppStyles.textStyleCaption,
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
                  child: SafeComboBox<String>(
                    value: _selectedConnection,
                    isExpanded: true,
                    placeholder: Text(context.l10n.selectConnection),
                    emptyPlaceholder: context.l10n.selectConnection,
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
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _remotePathController,
                        placeholder: context.l10n.remotePathPlaceholder,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: _chooseRemotePath,
                      child: const Text('可视化选择'),
                    ),
                  ],
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
                    // 构建忽略配置
                    final ignoreConfig = IgnoreConfig(
                      patterns: _ignorePatternsController.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                      extensions: _ignoreExtensionsController.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                      folders: _ignoreFoldersController.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                    );

                    await RepositoryManager.instance.importExisting(
                      _pathController.text,
                      name: _nameController.text.isEmpty
                          ? null
                          : _nameController.text,
                      ignoreConfig: ignoreConfig,
                      remoteName: _selectedConnection,
                      remotePath: _remotePathController.text.isEmpty
                          ? null
                          : _remotePathController.text,
                      maxVersions: _maxVersions,
                      maxVersionDays: _maxVersionDays,
                      maxVersionSizeGB: _maxVersionSizeGB,
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

  Future<void> _chooseRemotePath() async {
    final selectedConnection = _selectedConnection;
    if (selectedConnection == null) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _RemotePathPickerDialog(
        connectionName: selectedConnection,
        initialPath: _remotePathController.text.trim().isEmpty
            ? '/'
            : _remotePathController.text.trim(),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _remotePathController.text = selected);
  }

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
                  child: SafeComboBox<String>(
                    value: _selectedConnection,
                    isExpanded: true,
                    placeholder: const Text('Select connection...'),
                    emptyPlaceholder: 'Select connection...',
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
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _remotePathController,
                      placeholder: '/path/to/repository',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: _selectedConnection == null
                        ? null
                        : _chooseRemotePath,
                    child: const Text('可视化选择'),
                  ),
                ],
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
                    child: Text(context.l10n.browse),
                    onPressed: () async {
                      final result = await FilePicker.platform
                          .getDirectoryPath();
                      if (result != null) {
                        _localPathController.text = result;
                      }
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

class _RepositoryLocalSettingsDialog extends StatefulWidget {
  final Repository repository;

  const _RepositoryLocalSettingsDialog({required this.repository});

  @override
  State<_RepositoryLocalSettingsDialog> createState() =>
      _RepositoryLocalSettingsDialogState();
}

class _RepositoryLocalSettingsDialogState
    extends State<_RepositoryLocalSettingsDialog> {
  int _maxVersions = AppConstants.defaultMaxVersions;
  int _maxVersionDays = AppConstants.defaultMaxVersionDays;
  int _maxVersionSizeGB = AppConstants.defaultMaxVersionSizeGB;
  bool _loading = true;
  bool _saving = false;
  bool _estimating = false;
  int? _estimatedExtraBytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await RepositoryLocalSettingsService.instance.getSettings(
      widget.repository.id,
    );
    if (!mounted) return;
    setState(() {
      _maxVersions = settings.maxVersions;
      _maxVersionDays = settings.maxVersionDays;
      _maxVersionSizeGB = settings.maxVersionSizeGB;
      _loading = false;
    });
    await _recalculateEstimate();
  }

  Future<void> _recalculateEstimate() async {
    setState(() => _estimating = true);
    try {
      final estimate = await StorageEstimatorService.instance
          .estimateRetentionOverhead(
            rootPath: widget.repository.localPath,
            maxVersions: _maxVersions,
            maxDays: _maxVersionDays,
            maxSizeGB: _maxVersionSizeGB,
          );
      if (!mounted) return;
      setState(() => _estimatedExtraBytes = estimate.estimatedExtraBytes);
    } finally {
      if (mounted) {
        setState(() => _estimating = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(value >= 100
        ? 0
        : value >= 10
        ? 1
        : 2)} ${units[index]}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final existing = await RepositoryLocalSettingsService.instance
          .getSettings(widget.repository.id);
      await RepositoryLocalSettingsService.instance.saveSettings(
        existing.copyWith(
          maxVersions: _maxVersions,
          maxVersionDays: _maxVersionDays,
          maxVersionSizeGB: _maxVersionSizeGB,
          updatedAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('版本保留设置（本机）'),
      constraints: const BoxConstraints(maxWidth: 560),
      content: _loading
          ? const SizedBox(height: 120, child: Center(child: ProgressRing()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.repository.name,
                  style: AppStyles.textStyleSubtitle,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.repository.localPath,
                  style: AppStyles.textStyleCaption,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InfoLabel(
                        label: '保留版本数',
                        child: NumberBox(
                          value: _maxVersions.toDouble(),
                          min: 1,
                          max: 500,
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _maxVersions = value.toInt());
                            await _recalculateEstimate();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InfoLabel(
                        label: '保留天数',
                        child: NumberBox(
                          value: _maxVersionDays.toDouble(),
                          min: 1,
                          max: 3650,
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _maxVersionDays = value.toInt());
                            await _recalculateEstimate();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InfoLabel(
                        label: '容量上限(GB)',
                        child: NumberBox(
                          value: _maxVersionSizeGB.toDouble(),
                          min: 1,
                          max: 10000,
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _maxVersionSizeGB = value.toInt());
                            await _recalculateEstimate();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _estimating
                    ? const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('正在估算额外占用...'),
                        ],
                      )
                    : Text(
                        _estimatedExtraBytes == null
                            ? '无法估算额外占用。'
                            : '预计额外占用: ${_formatBytes(_estimatedExtraBytes!)}（基于仓库结构的动态估算）',
                        style: AppStyles.textStyleCaption,
                      ),
                const SizedBox(height: 8),
                const InfoBar(
                  severity: InfoBarSeverity.info,
                  title: Text('说明'),
                  content: Text('该配置仅保存在本机软件数据库，不会同步到仓库。'),
                ),
              ],
            ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _RemotePathPickerDialog extends StatefulWidget {
  final String connectionName;
  final String initialPath;

  const _RemotePathPickerDialog({
    required this.connectionName,
    this.initialPath = '/',
  });

  @override
  State<_RemotePathPickerDialog> createState() =>
      _RemotePathPickerDialogState();
}

class _RemotePathPickerDialogState extends State<_RemotePathPickerDialog> {
  final _newFolderController = TextEditingController();
  String _currentPath = '/';
  bool _loading = true;
  bool _creatingFolder = false;
  String? _error;
  List<RemoteDirectoryItem> _items = [];
  bool _supportsBrowser = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath.trim().isEmpty
        ? '/'
        : widget.initialPath.trim();
    _prepareAndLoad();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _prepareAndLoad() async {
    final conn = await RemoteConnectionManager.instance.getConnectionByName(
      widget.connectionName,
    );
    if (conn != null) {
      _supportsBrowser = RemoteConnectionManager.instance
          .supportsRemotePathBrowser(conn);
    }
    await _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_supportsBrowser) {
        final dirs = await RemoteConnectionManager.instance
            .listRemoteDirectories(
              connectionName: widget.connectionName,
              remotePath: _currentPath,
            );
        if (!mounted) return;
        setState(() => _items = dirs);
      } else {
        setState(() => _items = const []);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goParent() async {
    final compact = _currentPath.replaceAll('\\', '/');
    if (compact == '/' || compact.isEmpty) return;
    final parts = compact.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      _currentPath = '/';
    } else {
      parts.removeLast();
      _currentPath = parts.isEmpty ? '/' : '/${parts.join('/')}';
    }
    await _loadDirectories();
  }

  Future<void> _createFolder() async {
    final folderName = _newFolderController.text.trim();
    if (folderName.isEmpty) return;
    setState(() => _creatingFolder = true);
    try {
      final target = _currentPath == '/'
          ? '/$folderName'
          : '${_currentPath.endsWith('/') ? _currentPath.substring(0, _currentPath.length - 1) : _currentPath}/$folderName';
      await RemoteConnectionManager.instance.createRemoteDirectory(
        connectionName: widget.connectionName,
        remotePath: target,
      );
      _newFolderController.clear();
      await _loadDirectories();
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('创建目录失败'),
          content: Text('$e'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _creatingFolder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('选择远程路径'),
      constraints: const BoxConstraints(maxWidth: 620),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.connectionName, style: AppStyles.textStyleSubtitle),
          const SizedBox(height: 8),
          Row(
            children: [
              Button(onPressed: _goParent, child: const Text('上一级')),
              const SizedBox(width: 8),
              Button(onPressed: _loadDirectories, child: const Text('刷新')),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _currentPath,
                  style: AppStyles.textStyleBody,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_supportsBrowser)
            Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _newFolderController,
                    placeholder: '新建文件夹名',
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: _creatingFolder ? null : _createFolder,
                  child: _creatingFolder
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('新建文件夹'),
                ),
              ],
            )
          else
            const InfoBar(
              severity: InfoBarSeverity.warning,
              title: Text('当前协议不支持可视化浏览'),
              content: Text('可继续使用当前路径，或返回手动输入。'),
            ),
          const SizedBox(height: 8),
          Container(
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppStyles.borderColor(false)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _loading
                ? const Center(child: ProgressRing())
                : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                ? const Center(child: Text('当前目录没有可进入的子目录'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile.selectable(
                        title: Text(item.name),
                        leading: const Icon(FluentIcons.fabric_folder),
                        onPressed: () async {
                          _currentPath = item.path;
                          await _loadDirectories();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _currentPath),
          child: const Text('使用当前路径'),
        ),
      ],
    );
  }
}

/// 删除仓库结果
class _DeleteRepositoryResult {
  final bool deleteNanosyncFolder;

  const _DeleteRepositoryResult({required this.deleteNanosyncFolder});
}

/// 删除仓库确认对话框
class _DeleteRepositoryDialog extends StatefulWidget {
  final String repositoryName;

  const _DeleteRepositoryDialog({required this.repositoryName});

  @override
  State<_DeleteRepositoryDialog> createState() =>
      _DeleteRepositoryDialogState();
}

class _DeleteRepositoryDialogState extends State<_DeleteRepositoryDialog> {
  bool _deleteNanosyncFolder = false;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(context.l10n.deleteRepository),
      constraints: const BoxConstraints(maxWidth: 400),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.deleteRepositoryConfirm(widget.repositoryName),
            style: AppStyles.textStyleBody,
          ),
          const SizedBox(height: 16),
          Checkbox(
            checked: _deleteNanosyncFolder,
            onChanged: (v) =>
                setState(() => _deleteNanosyncFolder = v ?? false),
            content: Text(context.l10n.deleteNanosyncFolder),
          ),
          const SizedBox(height: 8),
          InfoBar(
            title: Text(context.l10n.notice),
            content: Text(
              _deleteNanosyncFolder
                  ? context.l10n.deleteNanosyncFolderHint
                  : context.l10n.deleteRepositoryHint,
            ),
            severity: _deleteNanosyncFolder
                ? InfoBarSeverity.error
                : InfoBarSeverity.warning,
          ),
        ],
      ),
      actions: [
        Button(
          child: Text(context.l10n.cancel),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          child: Text(context.l10n.delete),
          onPressed: () => Navigator.pop(
            context,
            _DeleteRepositoryResult(
              deleteNanosyncFolder: _deleteNanosyncFolder,
            ),
          ),
        ),
      ],
    );
  }
}

/// 迁移仓库对话框
class _MigrateRepositoryDialog extends StatefulWidget {
  final Repository repository;
  final VoidCallback onMigrated;

  const _MigrateRepositoryDialog({
    required this.repository,
    required this.onMigrated,
  });

  @override
  State<_MigrateRepositoryDialog> createState() =>
      _MigrateRepositoryDialogState();
}

class _MigrateRepositoryDialogState extends State<_MigrateRepositoryDialog> {
  final _pathController = TextEditingController();
  double _progress = 0;
  String _status = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pathController.text = widget.repository.localPath;
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(context.l10n.migrateRepository),
      constraints: const BoxConstraints(maxWidth: 500),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLabel(
              label: context.l10n.currentPath,
              child: TextBox(
                readOnly: true,
                controller: TextEditingController(
                  text: widget.repository.localPath,
                ),
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: context.l10n.newPath,
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
                    child: Text(context.l10n.browse),
                    onPressed: () async {
                      final result = await FilePicker.platform
                          .getDirectoryPath();
                      if (result != null) {
                        setState(() {
                          _pathController.text = result;
                        });
                      }
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
          child: Text(context.l10n.cancel),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        FilledButton(
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(context.l10n.migrate),
          onPressed: _isLoading || _pathController.text.isEmpty
              ? null
              : () async {
                  if (_pathController.text == widget.repository.localPath) {
                    await showDialog(
                      context: context,
                      builder: (context) => ContentDialog(
                        title: Text(context.l10n.error),
                        content: Text(context.l10n.samePathError),
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
                    await RepositoryManager.instance.migrateRepository(
                      widget.repository.id,
                      _pathController.text,
                      onProgress: (progress, message) {
                        setState(() {
                          _progress = progress;
                          _status = message;
                        });
                      },
                    );
                    widget.onMigrated();
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      await showDialog(
                        context: context,
                        builder: (context) => ContentDialog(
                          title: Text(context.l10n.error),
                          content: Text('${context.l10n.migrateFailed}: $e'),
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
                },
        ),
      ],
    );
  }
}
