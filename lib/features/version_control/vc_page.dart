import 'package:fluent_ui/fluent_ui.dart' hide ComboBoxItem;
import 'package:provider/provider.dart';
import '../../data/models/vc_models.dart';
import '../../data/services/vc_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/vc_repository_provider.dart';
import '../../shared/widgets/components/safe_combo_box.dart';
import 'widgets/diff_viewer.dart';
import 'widgets/file_tree_widget.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import '../../l10n/l10n.dart';

class VersionControlPage extends StatefulWidget {
  final String? repositoryId;

  const VersionControlPage({super.key, this.repositoryId});

  @override
  State<VersionControlPage> createState() => _VersionControlPageState();
}

class _VersionControlPageState extends State<VersionControlPage> {
  VcEngine? _engine;
  VcRepositoryStatus? _status;
  List<VcStagingEntry> _stagedChanges = [];
  List<VcFileChange> _unstagedChanges = [];
  List<VcConflictFile> _conflicts = [];
  List<VcCommit> _commitHistory = [];
  List<VcBranch> _branches = [];
  List<VcStash> _stashes = [];

  bool _loading = false;
  String _commitMessage = '';
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePage();
    });
  }

  Future<void> _initializePage() async {
    final vcProvider = context.read<VcRepositoryProvider>();
    await vcProvider.loadRepositories();

    if (widget.repositoryId != null) {
      _bindRepository(widget.repositoryId);
    } else if (vcProvider.repositories.isNotEmpty) {
      _bindRepository(vcProvider.repositories.first.id);
    }
  }

  @override
  void didUpdateWidget(covariant VersionControlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repositoryId != widget.repositoryId) {
      _bindRepository(widget.repositoryId);
    }
  }

  void _bindRepository(String? repositoryId) {
    if (repositoryId == null) {
      _engine = null;
      _status = null;
      _stagedChanges = [];
      _unstagedChanges = [];
      _conflicts = [];
      _commitHistory = [];
      _branches = [];
      _stashes = [];
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _engine = VcEngine(repositoryId: repositoryId);
    _loadData();
  }

  Future<void> _loadData() async {
    if (_engine == null) return;

    setState(() => _loading = true);

    try {
      final statusResult = await _engine!.status();
      if (statusResult.isSuccess) {
        _status = statusResult.data as VcRepositoryStatus;
      }

      _stagedChanges = await _engine!.getStagedChanges();
      _unstagedChanges = await _engine!.getUnstagedChanges();
      _conflicts = await _engine!.detectConflicts();
      _commitHistory = await _engine!.log(limit: 50);
      _branches = await _engine!.listBranches();
      _stashes = await _engine!.listStashes();
    } catch (e) {
      if (mounted) {
        _showError('加载数据失败: $e');
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          Button(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.teal),
    );
  }

  Future<void> _showStagedDiff(String relativePath) async {
    if (_engine == null) return;
    final diffs = await _engine!.diff(cached: true);
    final target = diffs.where((d) => d.relativePath == relativePath).toList();

    if (target.isEmpty) {
      _showError('该文件暂无可展示的差异，请先暂存后重试');
      return;
    }

    if (!mounted) return;
    _showDiffDialog('文件差异: $relativePath', target);
  }

  Future<void> _showCommitDiff(VcCommit commit) async {
    if (_engine == null) return;
    if (commit.parentCommitId.isEmpty) {
      _showError('初始提交暂不支持父提交对比');
      return;
    }

    final diffs = await _engine!.diff(
      commitId1: commit.parentCommitId,
      commitId2: commit.id,
    );

    if (diffs.isEmpty) {
      _showError('该提交未检测到可展示差异');
      return;
    }

    if (!mounted) return;
    _showDiffDialog('提交差异: ${commit.shortId}', diffs);
  }

  Future<void> _showWorkingDiff(String relativePath) async {
    if (_engine == null) return;

    final diffs = await _engine!.diff();
    final target = diffs.where((d) => d.relativePath == relativePath).toList();
    if (target.isEmpty) {
      _showError('该文件当前没有可展示差异');
      return;
    }

    if (!mounted) return;
    _showDiffDialog('工作区差异: $relativePath', target);
  }

  Future<void> _resolveConflict(
    VcConflictFile conflict,
    VcConflictResolutionStrategy strategy,
  ) async {
    if (_engine == null) return;

    final result = await _engine!.resolveConflict(
      relativePath: conflict.relativePath,
      strategy: strategy,
    );

    if (result.isSuccess) {
      _showSuccess(result.message);
      await _loadData();
    } else {
      _showError(result.message);
    }
  }

  void _showDiffDialog(String title, List<VcFileDiff> diffs) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(title),
        content: SizedBox(
          width: 1100,
          height: 700,
          child: DiffViewer(diffs: diffs),
        ),
        actions: [
          Button(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vcProvider = context.watch<VcRepositoryProvider>();

    return ScaffoldPage(
      header: PageHeader(
        title: Text(context.l10n.versionControlPageTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            if (_engine != null) ...[
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                label: const Text('刷新'),
                onPressed: _loading ? null : _loadData,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.git_graph),
                label: const Text('分支'),
                onPressed: _showBranchDialog,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.archive),
                label: const Text('Stash'),
                onPressed: _showStashDialog,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.warning),
                label: Text('冲突(${_conflicts.length})'),
                onPressed: () => setState(() => _selectedTabIndex = 3),
              ),
            ],
          ],
        ),
      ),
      content: Column(
        children: [
          // 仓库选择器
          _buildRepositorySelectorBar(vcProvider, isDark),
          // 主内容区域
          Expanded(child: _buildMainContent(vcProvider, isDark)),
        ],
      ),
    );
  }

  Widget _buildRepositorySelectorBar(
    VcRepositoryProvider vcProvider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppStyles.hoverBackground(isDark),
        border: Border(
          bottom: BorderSide(color: AppStyles.borderColor(isDark)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.folder_open,
            size: 16,
            color: isDark ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 8),
          Text(
            '选择仓库:',
            style: AppStyles.textStyleBody.copyWith(
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SafeComboBox<String>(
              value: vcProvider.currentRepository?.id,
              isExpanded: true,
              emptyPlaceholder: '暂无已注册仓库',
              items: vcProvider.repositories
                  .map(
                    (repo) => ComboBoxItem(
                      value: repo.id,
                      child: Row(
                        children: [
                          const Icon(FluentIcons.git_graph, size: 14),
                          const SizedBox(width: 8),
                          Text(repo.name),
                          if (repo.localPath.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '(${repo.localPath})',
                              style: AppStyles.textStyleCaption.copyWith(
                                color: AppStyles.lightTextSecondary(isDark),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  vcProvider.selectRepository(value);
                  _bindRepository(value);
                }
              },
            ),
          ),
          if (vcProvider.repositories.isNotEmpty) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: '刷新仓库列表',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: () => vcProvider.loadRepositories(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(VcRepositoryProvider vcProvider, bool isDark) {
    // 如果没有已注册仓库，显示提示信息
    if (vcProvider.repositories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.git_graph, size: 64),
            const SizedBox(height: 16),
            Text('暂无已注册仓库', style: AppStyles.textStyleSubtitle),
            const SizedBox(height: 8),
            Text(
              '请先在"仓库"页面导入或克隆仓库',
              style: AppStyles.textStyleBody.copyWith(
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Button(
              onPressed: () {
                // 导航到仓库页面
              },
              child: const Text('前往仓库页面'),
            ),
          ],
        ),
      );
    }

    // 如果没有选择仓库
    if (_engine == null) {
      return const Center(child: ProgressRing());
    }

    // 显示加载中
    if (_loading) {
      return const Center(child: ProgressRing());
    }

    return Column(
      children: [
        _buildTabBar(isDark),
        Expanded(child: _buildTabContent(isDark)),
      ],
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppStyles.hoverBackground(isDark),
        border: Border(
          bottom: BorderSide(color: AppStyles.borderColor(isDark)),
        ),
      ),
      child: Row(
        children: [
          _buildTab(0, '工作区', FluentIcons.edit, isDark),
          _buildTab(1, '历史', FluentIcons.history, isDark),
          _buildTab(2, '分支', FluentIcons.git_graph, isDark),
          _buildTab(3, '冲突', FluentIcons.warning, isDark),
          _buildTab(4, 'Stash', FluentIcons.archive, isDark),
          _buildTab(
            5,
            context.l10n.fileManagement,
            FluentIcons.folder_open,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon, bool isDark) {
    final theme = FluentTheme.of(context);
    final isSelected = _selectedTabIndex == index;
    final unselectedColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? theme.accentColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? theme.accentColor : unselectedColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppStyles.textStyleBody.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? theme.accentColor : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isDark) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildWorkspaceTab(isDark);
      case 1:
        return _buildHistoryTab(isDark);
      case 2:
        return _buildBranchesTab(isDark);
      case 3:
        return _buildConflictsTab(isDark);
      case 4:
        return _buildStashTab(isDark);
      case 5:
        return _buildFileManagementTab(isDark);
      default:
        return const SizedBox();
    }
  }

  Widget _buildWorkspaceTab(bool isDark) {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildChangesPanel(isDark)),
        Container(width: 1, color: isDark ? Colors.grey[80] : Colors.grey[40]),
        Expanded(flex: 1, child: _buildCommitPanel(isDark)),
      ],
    );
  }

  Widget _buildChangesPanel(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChangesSection(
          '暂存区 (${_stagedChanges.length})',
          _stagedChanges
              .map((e) => _buildStagingEntryItem(e, true, isDark))
              .toList(),
          isDark,
        ),
        const Divider(),
        _buildChangesSection(
          '未暂存 (${_unstagedChanges.length})',
          _unstagedChanges.map((e) => _buildFileChangeItem(e, isDark)).toList(),
          isDark,
        ),
      ],
    );
  }

  Widget _buildChangesSection(String title, List<Widget> items, bool isDark) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppStyles.hoverBackground(isDark)),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppStyles.textStyleButton.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                if (items.isNotEmpty) ...[
                  if (title.contains('暂存区'))
                    HyperlinkButton(
                      onPressed: () async {
                        await _engine?.reset(all: true);
                        _loadData();
                      },
                      child: Text('取消暂存', style: AppStyles.textStyleCaption),
                    )
                  else
                    HyperlinkButton(
                      onPressed: () async {
                        await _engine?.add(all: true);
                        _loadData();
                      },
                      child: Text('暂存全部', style: AppStyles.textStyleCaption),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      '无更改',
                      style: AppStyles.textStyleBody.copyWith(
                        color: AppStyles.lightTextSecondary(isDark),
                      ),
                    ),
                  )
                : ListView(children: items),
          ),
        ],
      ),
    );
  }

  Widget _buildStagingEntryItem(
    VcStagingEntry entry,
    bool staged,
    bool isDark,
  ) {
    final changeType = VcChangeType.values.firstWhere(
      (e) => e.name == entry.changeType,
      orElse: () => VcChangeType.modified,
    );

    return HoverButton(
      onPressed: () => _showStagedDiff(entry.relativePath),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: states.isHovered
            ? (isDark ? Colors.white.withAlpha(10) : Colors.grey[20])
            : null,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getChangeTypeColor(changeType),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getChangeTypeIcon(changeType),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.relativePath,
                overflow: TextOverflow.ellipsis,
                style: AppStyles.textStyleBody.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            if (staged)
              IconButton(
                icon: const Icon(FluentIcons.remove, size: 14),
                onPressed: () async {
                  await _engine?.reset(files: [entry.relativePath]);
                  _loadData();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileChangeItem(VcFileChange change, bool isDark) {
    return HoverButton(
      onPressed: () => _showError('未暂存变更请先点击右侧 + 按钮暂存后再查看差异'),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: states.isHovered
            ? (isDark ? Colors.white.withAlpha(10) : Colors.grey[20])
            : null,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getChangeTypeColor(change.changeType),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                change.changeTypeIcon,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                change.relativePath,
                overflow: TextOverflow.ellipsis,
                style: AppStyles.textStyleBody.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.add, size: 14),
              onPressed: () async {
                await _engine?.add(files: [change.relativePath]);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getChangeTypeColor(VcChangeType type) {
    switch (type) {
      case VcChangeType.added:
        return Colors.green;
      case VcChangeType.modified:
        return Colors.orange;
      case VcChangeType.deleted:
        return Colors.red;
      case VcChangeType.renamed:
        return Colors.blue;
      case VcChangeType.copied:
        return Colors.purple;
    }
  }

  String _getChangeTypeIcon(VcChangeType type) {
    switch (type) {
      case VcChangeType.added:
        return 'A';
      case VcChangeType.modified:
        return 'M';
      case VcChangeType.deleted:
        return 'D';
      case VcChangeType.renamed:
        return 'R';
      case VcChangeType.copied:
        return 'C';
    }
  }

  Widget _buildCommitPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '提交',
            style: AppStyles.textStyleSubtitle.copyWith(
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          TextFormBox(
            placeholder: '提交信息',
            maxLines: 4,
            onChanged: (value) => _commitMessage = value,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _stagedChanges.isEmpty || _commitMessage.isEmpty
                      ? null
                      : () async {
                          final result = await _engine?.commit(
                            message: _commitMessage,
                          );
                          if (result?.isSuccess == true) {
                            _showSuccess(result!.message);
                            _commitMessage = '';
                            _loadData();
                          } else {
                            _showError(result?.message ?? '提交失败');
                          }
                        },
                  child: const Text('提交'),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(),
          Text(
            '快捷操作',
            style: AppStyles.textStyleCaption.copyWith(
              color: isDark ? Colors.grey[100] : Colors.grey[140],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HyperlinkButton(
                onPressed: () async {
                  await _engine?.add(all: true);
                  _loadData();
                },
                child: Text('暂存全部', style: AppStyles.textStyleCaption),
              ),
              HyperlinkButton(
                onPressed: () async {
                  await _engine?.reset(all: true);
                  _loadData();
                },
                child: Text('取消全部暂存', style: AppStyles.textStyleCaption),
              ),
              HyperlinkButton(
                onPressed: () => _showResetDialog(),
                child: Text('硬重置', style: AppStyles.textStyleCaption),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(bool isDark) {
    if (_commitHistory.isEmpty) {
      return Center(
        child: Text(
          '暂无提交历史',
          style: AppStyles.textStyleBody.copyWith(
            color: AppStyles.lightTextSecondary(isDark),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _commitHistory.length,
      itemBuilder: (context, index) {
        final commit = _commitHistory[index];
        return _buildCommitItem(commit, isDark);
      },
    );
  }

  Widget _buildCommitItem(VcCommit commit, bool isDark) {
    return HoverButton(
      onPressed: () => _showCommitDetail(commit),
      builder: (context, states) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppStyles.dividerColor(isDark)),
          ),
          color: states.isHovered ? AppStyles.hoverBackground(isDark) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FluentTheme.of(context).accentColor.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  commit.shortId,
                  style: AppStyles.textStyleCaption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: FluentTheme.of(context).accentColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commit.shortMessage,
                    style: AppStyles.textStyleButton.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        FluentIcons.contact,
                        size: 12,
                        color: AppStyles.lightTextSecondary(isDark),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        commit.authorName,
                        style: AppStyles.textStyleCaption.copyWith(
                          color: AppStyles.lightTextSecondary(isDark),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        FluentIcons.clock,
                        size: 12,
                        color: AppStyles.lightTextSecondary(isDark),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(commit.committedAt),
                        style: AppStyles.textStyleCaption.copyWith(
                          color: AppStyles.lightTextSecondary(isDark),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${commit.additions} -${commit.deletions}',
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.lightTextSecondary(isDark),
                  ),
                ),
                Text(
                  '${commit.fileCount} 文件',
                  style: AppStyles.textStyleCaption.copyWith(
                    color: AppStyles.lightTextSecondary(isDark),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchesTab(bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppStyles.hoverBackground(isDark)),
          child: Row(
            children: [
              Text(
                '分支列表',
                style: AppStyles.textStyleButton.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              Button(
                onPressed: () => _showCreateBranchDialog(),
                child: const Text('新建分支'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _branches.isEmpty
              ? Center(
                  child: Text(
                    '暂无分支',
                    style: AppStyles.textStyleBody.copyWith(
                      color: AppStyles.lightTextSecondary(isDark),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _branches.length,
                  itemBuilder: (context, index) {
                    final branch = _branches[index];
                    final isCurrentBranch = _status?.branchName == branch.name;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppStyles.dividerColor(isDark),
                          ),
                        ),
                        color: isCurrentBranch
                            ? FluentTheme.of(context).accentColor.withAlpha(20)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCurrentBranch
                                ? FluentIcons.check_mark
                                : FluentIcons.git_graph,
                            color: isCurrentBranch
                                ? FluentTheme.of(context).accentColor
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              branch.name + (branch.isDefault ? ' (默认)' : ''),
                              style: AppStyles.textStyleBody.copyWith(
                                fontWeight: isCurrentBranch
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          if (!isCurrentBranch) ...[
                            IconButton(
                              icon: const Icon(FluentIcons.switch_widget),
                              onPressed: () async {
                                final result = await _engine?.checkout(
                                  branchName: branch.name,
                                );
                                if (result?.isSuccess == true) {
                                  _showSuccess('已切换到分支 ${branch.name}');
                                  _loadData();
                                } else {
                                  _showError(result?.message ?? '切换失败');
                                }
                              },
                            ),
                            if (!branch.isDefault)
                              IconButton(
                                icon: const Icon(FluentIcons.delete),
                                onPressed: () => _deleteBranch(branch),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStashTab(bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppStyles.hoverBackground(isDark)),
          child: Row(
            children: [
              Text(
                'Stash 列表',
                style: AppStyles.textStyleButton.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              Button(
                onPressed: () async {
                  final result = await _engine?.stash();
                  if (result?.isSuccess == true) {
                    _showSuccess(result!.message);
                    _loadData();
                  } else {
                    _showError(result?.message ?? 'Stash 失败');
                  }
                },
                child: const Text('创建 Stash'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _stashes.isEmpty
              ? Center(
                  child: Text(
                    '暂无 Stash',
                    style: AppStyles.textStyleBody.copyWith(
                      color: AppStyles.lightTextSecondary(isDark),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _stashes.length,
                  itemBuilder: (context, index) {
                    final stash = _stashes[index];

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppStyles.dividerColor(isDark),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.teal.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                stash.shortId,
                                style: AppStyles.textStyleCaption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stash.message,
                                  style: AppStyles.textStyleBody.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  '${stash.fileCount} 文件 | ${_formatTime(stash.createdAt)}',
                                  style: AppStyles.textStyleCaption.copyWith(
                                    color: AppStyles.lightTextSecondary(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(FluentIcons.undo),
                            onPressed: () async {
                              final result = await _engine?.stashPop(
                                stashId: stash.id,
                              );
                              if (result?.isSuccess == true) {
                                _showSuccess(result!.message);
                                _loadData();
                              } else {
                                _showError(result?.message ?? 'Pop 失败');
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(FluentIcons.delete),
                            onPressed: () async {
                              final result = await _engine?.deleteStash(
                                stash.id,
                              );
                              if (result?.isSuccess == true) {
                                _showSuccess(result!.message);
                                _loadData();
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileManagementTab(bool isDark) {
    if (_engine == null) {
      return Center(
        child: Text(
          context.l10n.selectRepositoryFirst,
          style: AppStyles.textStyleBody.copyWith(
            color: AppStyles.lightTextSecondary(isDark),
          ),
        ),
      );
    }

    return FileTreeWidget(
      engine: _engine!,
      onRulesChanged: () {
        // 规则变更后重新加载数据
        _loadData();
      },
    );
  }

  Widget _buildConflictsTab(bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppStyles.hoverBackground(isDark),
            border: Border(
              bottom: BorderSide(color: AppStyles.dividerColor(isDark)),
            ),
          ),
          child: Row(
            children: [
              Text(
                '冲突文件 (${_conflicts.length})',
                style: AppStyles.textStyleButton.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              Button(
                onPressed: _loading ? null : _loadData,
                child: const Text('重新检测'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _conflicts.isEmpty
              ? Center(
                  child: Text(
                    '未检测到冲突',
                    style: AppStyles.textStyleBody.copyWith(
                      color: AppStyles.lightTextSecondary(isDark),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _conflicts.length,
                  itemBuilder: (context, index) {
                    final conflict = _conflicts[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppStyles.dividerColor(isDark),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            FluentIcons.warning,
                            color: AppStyles.warningColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conflict.relativePath,
                                  style: AppStyles.textStyleButton.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  '${conflict.markerBlocks} 个冲突块${conflict.isStaged ? ' | 已暂存' : ''}',
                                  style: AppStyles.textStyleCaption.copyWith(
                                    color: AppStyles.lightTextSecondary(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: '保留 <<<<<<< 与 ======= 之间内容',
                            child: Button(
                              onPressed: () => _resolveConflict(
                                conflict,
                                VcConflictResolutionStrategy.ours,
                              ),
                              child: const Text('用本地块'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: '保留 ======= 与 >>>>>>> 之间内容',
                            child: Button(
                              onPressed: () => _resolveConflict(
                                conflict,
                                VcConflictResolutionStrategy.theirs,
                              ),
                              child: const Text('用远端块'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Button(
                            onPressed: () =>
                                _showWorkingDiff(conflict.relativePath),
                            child: const Text('查看Diff'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showBranchDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('分支管理'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: Column(
            children: [
              TextBox(
                placeholder: '新分支名称',
                onSubmitted: (value) async {
                  if (value.isNotEmpty) {
                    final result = await _engine?.branch(name: value);
                    if (result?.isSuccess == true) {
                      if (mounted) {
                        Navigator.pop(context);
                        _showSuccess(result!.message);
                        _loadData();
                      }
                    } else {
                      _showError(result?.message ?? '创建失败');
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _branches.length,
                  itemBuilder: (context, index) {
                    final branch = _branches[index];
                    return ListTile(
                      title: Text(branch.name),
                      subtitle: Text(branch.isDefault ? '默认分支' : ''),
                      trailing: _status?.branchName == branch.name
                          ? const Icon(FluentIcons.check_mark)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showStashDialog() async {
    final result = await _engine?.stash();
    if (result?.isSuccess == true) {
      _showSuccess(result!.message);
      _loadData();
    } else {
      _showError(result?.message ?? 'Stash 失败');
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('硬重置'),
        content: const Text('警告：硬重置将丢弃所有未提交的更改！此操作不可撤销。'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('确定重置'),
            onPressed: () async {
              Navigator.pop(context);
              final result = await _engine?.reset(all: true, hard: true);
              if (result?.isSuccess == true) {
                _showSuccess(result!.message);
                _loadData();
              } else {
                _showError(result?.message ?? '重置失败');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showCommitDetail(VcCommit commit) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text('提交 ${commit.shortId}'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('提交信息:', style: FluentTheme.of(context).typography.caption),
              const SizedBox(height: 4),
              Text(commit.message),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '作者:',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        Text(commit.authorName),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '时间:',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        Text(_formatTime(commit.committedAt)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('统计:', style: FluentTheme.of(context).typography.caption),
              Text(
                '${commit.fileCount} 文件更改, +${commit.additions} -${commit.deletions}',
              ),
            ],
          ),
        ),
        actions: [
          Button(
            child: const Text('查看Diff'),
            onPressed: () async {
              Navigator.pop(context);
              await _showCommitDiff(commit);
            },
          ),
          Button(
            child: const Text('Revert'),
            onPressed: () async {
              Navigator.pop(context);
              final result = await _engine?.revert(commitId: commit.id);
              if (result?.isSuccess == true) {
                _showSuccess(result!.message);
                _loadData();
              } else {
                _showError(result?.message ?? 'Revert 失败');
              }
            },
          ),
          Button(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCreateBranchDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('创建新分支'),
        content: SizedBox(
          width: 300,
          child: TextBox(
            controller: controller,
            placeholder: '分支名称',
            autofocus: true,
          ),
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('创建'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(context);
              final result = await _engine?.branch(name: name);
              if (result?.isSuccess == true) {
                _showSuccess(result!.message);
                _loadData();
              } else {
                _showError(result?.message ?? '创建失败');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(VcBranch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('删除分支'),
        content: Text('确定要删除分支 "${branch.name}" 吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('删除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _engine?.deleteBranch(branch.name);
      if (result?.isSuccess == true) {
        _showSuccess(result!.message);
        _loadData();
      } else {
        _showError(result?.message ?? '删除失败');
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return '刚刚';
        }
        return '${diff.inMinutes} 分钟前';
      }
      return '${diff.inHours} 小时前';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    }
  }
}
