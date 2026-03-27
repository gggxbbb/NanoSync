import 'package:fluent_ui/fluent_ui.dart';
import '../../../data/services/vc_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

/// VcEngine的静态默认忽略规则（用于UI显示）
const List<String> _kDefaultIgnoreRules = [
  '.nanosync/',
  '.git/',
  'Thumbs.db',
  '.DS_Store',
];

/// 文件树管理组件，用于管理忽略/保留文件
class FileTreeWidget extends StatefulWidget {
  final VcEngine engine;
  final VoidCallback? onRulesChanged;

  const FileTreeWidget({super.key, required this.engine, this.onRulesChanged});

  @override
  State<FileTreeWidget> createState() => _FileTreeWidgetState();
}

class _FileTreeWidgetState extends State<FileTreeWidget> {
  List<VcFileTreeNode> _rootNodes = [];
  List<String> _ignoreRules = [];
  bool _loading = false;
  String? _currentPath;

  // 导航栈
  final List<String?> _navigationStack = [null];
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final nodes = await widget.engine.getFileTree(parentPath: _currentPath);
      final rules = await widget.engine.getIgnoreRules();

      if (mounted) {
        setState(() {
          _rootNodes = nodes;
          _ignoreRules = rules;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _navigateInto(String path) {
    _navigationStack.removeRange(_navIndex + 1, _navigationStack.length);
    _navigationStack.add(path);
    _navIndex = _navigationStack.length - 1;
    _currentPath = path;
    _loadData();
  }

  void _navigateBack() {
    if (_navIndex > 0) {
      _navIndex--;
      _currentPath = _navigationStack[_navIndex];
      _loadData();
    }
  }

  void _navigateForward() {
    if (_navIndex < _navigationStack.length - 1) {
      _navIndex++;
      _currentPath = _navigationStack[_navIndex];
      _loadData();
    }
  }

  Future<void> _toggleIgnore(VcFileTreeNode node) async {
    VcOperationResultData result;

    if (node.isIgnored) {
      result = await widget.engine.unignorePath(
        node.relativePath,
        isDirectory: node.isDirectory,
      );
    } else {
      result = await widget.engine.ignorePath(
        node.relativePath,
        isDirectory: node.isDirectory,
      );
    }

    if (result.isSuccess) {
      widget.onRulesChanged?.call();
      _loadData();
    } else {
      if (mounted) {
        _showError(result.message);
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(context.l10n.error),
        content: Text(message),
        actions: [
          Button(
            child: Text(context.l10n.ok),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showAddRuleDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(context.l10n.addIgnoreRule),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.enterIgnorePattern),
            const SizedBox(height: 12),
            TextBox(
              controller: controller,
              placeholder: context.l10n.patternExample,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.directoryRuleHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Button(
            child: Text(context.l10n.cancel),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: Text(context.l10n.create),
            onPressed: () async {
              final rule = controller.text.trim();
              if (rule.isEmpty) return;

              Navigator.pop(context);
              final result = await widget.engine.addIgnoreRule(rule);

              if (result.isSuccess) {
                widget.onRulesChanged?.call();
                _loadData();
              } else {
                _showError(result.message);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showRulesDialog() {
    showDialog(
      context: context,
      builder: (context) => _IgnoreRulesDialog(
        rules: _ignoreRules,
        defaultRules: _kDefaultIgnoreRules,
        onRemove: (rule) async {
          final result = await widget.engine.removeIgnoreRule(rule);
          if (result.isSuccess) {
            widget.onRulesChanged?.call();
            _loadData();
          }
          return result;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // 工具栏
        _buildToolbar(isDark),
        // 面包屑导航
        _buildBreadcrumb(isDark),
        // 文件列表
        Expanded(
          child: _loading
              ? const Center(child: ProgressRing())
              : _buildFileList(isDark),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppStyles.hoverBackground(isDark),
        border: Border(
          bottom: BorderSide(color: AppStyles.borderColor(isDark)),
        ),
      ),
      child: Row(
        children: [
          // 导航按钮
          IconButton(
            icon: Icon(
              FluentIcons.back,
              size: 16,
              color: _navIndex > 0
                  ? (isDark ? Colors.white : Colors.black)
                  : Colors.grey,
            ),
            onPressed: _navIndex > 0 ? _navigateBack : null,
          ),
          IconButton(
            icon: Icon(
              FluentIcons.forward,
              size: 16,
              color: _navIndex < _navigationStack.length - 1
                  ? (isDark ? Colors.white : Colors.black)
                  : Colors.grey,
            ),
            onPressed: _navIndex < _navigationStack.length - 1
                ? _navigateForward
                : null,
          ),
          IconButton(
            icon: Icon(
              FluentIcons.up,
              size: 16,
              color: _currentPath != null
                  ? (isDark ? Colors.white : Colors.black)
                  : Colors.grey,
            ),
            onPressed: _currentPath != null ? _navigateBack : null,
          ),
          IconButton(
            icon: Icon(
              FluentIcons.refresh,
              size: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _loading ? null : _loadData,
          ),
          const Spacer(),
          // 操作按钮
          Tooltip(
            message: context.l10n.addIgnoreRule,
            child: IconButton(
              icon: const Icon(FluentIcons.add, size: 16),
              onPressed: _showAddRuleDialog,
            ),
          ),
          Tooltip(
            message: context.l10n.viewAllRules,
            child: IconButton(
              icon: const Icon(FluentIcons.list, size: 16),
              onPressed: _showRulesDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(bool isDark) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a1a) : Colors.grey[10],
        border: Border(
          bottom: BorderSide(color: AppStyles.borderColor(isDark)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _navigationStack.removeRange(1, _navigationStack.length);
              _navIndex = 0;
              _currentPath = null;
              _loadData();
            },
            child: Text(
              context.l10n.rootDirectory,
              style: AppStyles.textStyleBody.copyWith(
                color: _currentPath == null
                    ? theme.accentColor
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: _currentPath == null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          if (_currentPath != null) ..._buildBreadcrumbItems(isDark),
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbItems(bool isDark) {
    final theme = FluentTheme.of(context);
    final parts = _currentPath!.split('/');
    final items = <Widget>[];
    var accumulatedPath = '';

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      accumulatedPath = accumulatedPath.isEmpty
          ? part
          : '$accumulatedPath/$part';
      final isLast = i == parts.length - 1;

      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            FluentIcons.chevron_right,
            size: 12,
            color: isDark ? Colors.grey[100] : Colors.grey[140],
          ),
        ),
      );

      items.add(
        GestureDetector(
          onTap: isLast
              ? null
              : () {
                  _currentPath = accumulatedPath;
                  _navIndex = i + 1;
                  _loadData();
                },
          child: Text(
            part,
            style: AppStyles.textStyleBody.copyWith(
              color: isLast
                  ? theme.accentColor
                  : (isDark ? Colors.white : Colors.black),
              fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildFileList(bool isDark) {
    if (_rootNodes.isEmpty) {
      return Center(
        child: Text(
          context.l10n.emptyDirectory,
          style: AppStyles.textStyleBody.copyWith(
            color: AppStyles.lightTextSecondary(isDark),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _rootNodes.length,
      itemBuilder: (context, index) {
        final node = _rootNodes[index];
        return _FileTreeItem(
          node: node,
          isDark: isDark,
          onTap: node.isDirectory
              ? () => _navigateInto(node.relativePath)
              : null,
          onToggleIgnore: () => _toggleIgnore(node),
        );
      },
    );
  }
}

/// 文件树项组件
class _FileTreeItem extends StatefulWidget {
  final VcFileTreeNode node;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback onToggleIgnore;

  const _FileTreeItem({
    required this.node,
    required this.isDark,
    this.onTap,
    required this.onToggleIgnore,
  });

  @override
  State<_FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends State<_FileTreeItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final icon = widget.node.isDirectory
        ? (widget.node.isIgnored ? FluentIcons.folder : FluentIcons.folder)
        : (widget.node.isIgnored
              ? FluentIcons.page
              : _getFileIcon(widget.node.name));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppStyles.hoverBackground(widget.isDark)
                : (widget.node.isIgnored
                      ? (widget.isDark
                            ? Colors.red.withAlpha(20)
                            : Colors.red.withAlpha(10))
                      : null),
            border: Border(
              bottom: BorderSide(color: AppStyles.dividerColor(widget.isDark)),
            ),
          ),
          child: Row(
            children: [
              // 图标
              Icon(
                icon,
                size: 18,
                color: widget.node.isIgnored
                    ? Colors.grey
                    : (widget.node.isDirectory
                          ? const Color(0xFFE8A838) // 文件夹黄色
                          : _getFileIconColor(widget.node.name)),
              ),
              const SizedBox(width: 10),
              // 名称
              Expanded(
                child: Text(
                  widget.node.name,
                  style: AppStyles.textStyleBody.copyWith(
                    color: widget.node.isIgnored
                        ? Colors.grey
                        : (widget.isDark ? Colors.white : Colors.black),
                    decoration: widget.node.isIgnored
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.node.isIgnored
                      ? Colors.red.withAlpha(widget.isDark ? 50 : 30)
                      : Colors.green.withAlpha(widget.isDark ? 50 : 30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.node.isIgnored
                      ? context.l10n.ignored
                      : context.l10n.tracked,
                  style: AppStyles.textStyleCaption.copyWith(
                    color: widget.node.isIgnored ? Colors.red : Colors.green,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 切换按钮
              Tooltip(
                message: widget.node.isIgnored
                    ? context.l10n.unignoreItem
                    : context.l10n.ignoreThisItem,
                child: IconButton(
                  icon: Icon(
                    widget.node.isIgnored
                        ? FluentIcons.checkbox_composite
                        : FluentIcons.checkbox,
                    size: 16,
                    color: widget.node.isIgnored
                        ? theme.accentColor
                        : Colors.grey,
                  ),
                  onPressed: widget.onToggleIgnore,
                ),
              ),
              // 进入目录按钮
              if (widget.node.isDirectory) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: context.l10n.enterDirectory,
                  child: IconButton(
                    icon: Icon(
                      FluentIcons.chevron_right,
                      size: 14,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                    onPressed: widget.onTap,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return FluentIcons.code;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return FluentIcons.code;
      case 'json':
        return FluentIcons.code;
      case 'md':
        return FluentIcons.text_document;
      case 'yaml':
      case 'yml':
        return FluentIcons.code;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return FluentIcons.photo2;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'webm':
        return FluentIcons.video;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return FluentIcons.music_in_collection;
      case 'pdf':
        return FluentIcons.bookmarks;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
        return FluentIcons.folder_open;
      case 'txt':
        return FluentIcons.text_document;
      case 'html':
      case 'css':
        return FluentIcons.code;
      default:
        return FluentIcons.page;
    }
  }

  Color _getFileIconColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return const Color(0xFF0175C2);
      case 'js':
        return const Color(0xFFF7DF1E);
      case 'ts':
        return const Color(0xFF3178C6);
      case 'json':
        return const Color(0xFFCB7C40);
      case 'md':
        return Colors.grey;
      case 'yaml':
      case 'yml':
        return const Color(0xFFCB171E);
      case 'png':
      case 'jpg':
      case 'gif':
      case 'svg':
        return const Color(0xFF9B59B6);
      case 'mp4':
      case 'avi':
        return Colors.teal;
      case 'mp3':
      case 'wav':
        return const Color(0xFFE91E63);
      case 'pdf':
        return Colors.red;
      case 'zip':
      case 'tar':
        return const Color(0xFF795548);
      case 'html':
        return const Color(0xFFE34F26);
      case 'css':
        return const Color(0xFF1572B6);
      default:
        return Colors.grey;
    }
  }
}

/// 忽略规则对话框
class _IgnoreRulesDialog extends StatefulWidget {
  final List<String> rules;
  final List<String> defaultRules;
  final Future<VcOperationResultData> Function(String) onRemove;

  const _IgnoreRulesDialog({
    required this.rules,
    required this.defaultRules,
    required this.onRemove,
  });

  @override
  State<_IgnoreRulesDialog> createState() => _IgnoreRulesDialogState();
}

class _IgnoreRulesDialogState extends State<_IgnoreRulesDialog> {
  bool _loading = false;
  String? _removingRule;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final customRules = widget.rules
        .where((r) => !widget.defaultRules.contains(r))
        .toList();

    return ContentDialog(
      title: Row(
        children: [
          Text(context.l10n.ignoreRuleList),
          const Spacer(),
          Text(
            context.l10n.ruleCount(widget.rules.length),
            style: AppStyles.textStyleCaption.copyWith(
              color: AppStyles.lightTextSecondary(isDark),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 默认规则
            Text(
              context.l10n.defaultRulesNotDeletable,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: widget.defaultRules.map((rule) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[80] : Colors.grey[30],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rule,
                    style: AppStyles.textStyleCaption.copyWith(
                      color: isDark ? Colors.grey[120] : Colors.grey[160],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // 自定义规则
            Text(
              context.l10n.customRules,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: customRules.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.noCustomRules,
                        style: AppStyles.textStyleBody.copyWith(
                          color: AppStyles.lightTextSecondary(isDark),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: customRules.length,
                      itemBuilder: (context, index) {
                        final rule = customRules[index];
                        final isRemoving = _loading && _removingRule == rule;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppStyles.dividerColor(isDark),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rule,
                                  style: AppStyles.textStyleBody.copyWith(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                              if (isRemoving)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: ProgressRing(strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  icon: const Icon(
                                    FluentIcons.delete,
                                    size: 14,
                                  ),
                                  onPressed: () async {
                                    setState(() {
                                      _loading = true;
                                      _removingRule = rule;
                                    });
                                    final result = await widget.onRemove(rule);
                                    if (mounted) {
                                      setState(() {
                                        _loading = false;
                                        _removingRule = null;
                                      });
                                      if (result.isSuccess) {
                                        Navigator.pop(context);
                                      }
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
        ),
      ),
      actions: [
        Button(
          child: const Text('关闭'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
