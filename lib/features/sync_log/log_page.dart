import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/app_log.dart';
import '../../data/services/app_log_service.dart';
import '../../shared/widgets/components/cards.dart';
import '../../shared/widgets/components/dialogs.dart';
import '../../shared/widgets/components/indicators.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final AppLogService _appLogService = AppLogService.instance;
  List<AppLog> _logs = [];
  bool _loading = true;
  String _searchQuery = '';
  String _selectedLevel = 'debug';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);

    final minLevel = _selectedLevel == 'all'
        ? null
        : AppLogLevel.values.firstWhere(
            (item) => item.name == _selectedLevel,
            orElse: () => AppLogLevel.debug,
          );

    final logs = await _appLogService.getLogs(limit: 1000, minLevel: minLevel);
    if (!mounted) {
      return;
    }

    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  List<AppLog> get _filteredLogs {
    if (_searchQuery.trim().isEmpty) {
      return _logs;
    }

    final keyword = _searchQuery.trim().toLowerCase();
    return _logs.where((log) {
      return log.message.toLowerCase().contains(keyword) ||
          log.category.toLowerCase().contains(keyword) ||
          log.details.toLowerCase().contains(keyword) ||
          log.source.toLowerCase().contains(keyword) ||
          log.operation.toLowerCase().contains(keyword) ||
          _contextText(log.context).toLowerCase().contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('应用日志'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: _loadLogs,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.delete),
              label: const Text('清空日志'),
              onPressed: _clearLogs,
            ),
          ],
        ),
      ),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    placeholder: '搜索日志（消息、模块、详情、上下文）',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.search, size: 16),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: InfoLabel(
                    label: '最小级别',
                    child: ComboBox<String>(
                      isExpanded: true,
                      value: _selectedLevel,
                      items: const [
                        ComboBoxItem(value: 'debug', child: Text('DEBUG+')),
                        ComboBoxItem(value: 'info', child: Text('INFO+')),
                        ComboBoxItem(value: 'warning', child: Text('WARNING+')),
                        ComboBoxItem(value: 'error', child: Text('ERROR')),
                        ComboBoxItem(value: 'all', child: Text('全部')),
                      ],
                      onChanged: (v) async {
                        if (v == null) {
                          return;
                        }
                        setState(() => _selectedLevel = v);
                        await _loadLogs();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: ProgressRing())
                : _filteredLogs.isEmpty
                ? const EmptyState(
                    icon: FluentIcons.list,
                    title: '暂无应用日志',
                    subtitle: '执行应用操作后，调试日志会显示在这里。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) =>
                        _buildLogCard(_filteredLogs[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(AppLog log) {
    final palette = _palette(log.level);

    return AppCardSurface(
      padding: EdgeInsets.zero,
      child: Expander(
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: palette.$2.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(palette.$1, color: palette.$2, size: 16),
        ),
        header: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppStyles.textStyleButton,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatTime(log.createdAt)} | ${log.level.name.toUpperCase()} | ${log.category}${log.operation.isEmpty ? '' : ' | ${log.operation}'}',
                    style: AppStyles.textStyleCaption,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('时间', _formatTime(log.createdAt)),
            _buildInfoRow('级别', log.level.name.toUpperCase()),
            _buildInfoRow('模块', log.category),
            _buildInfoRow('操作', log.operation.isEmpty ? '-' : log.operation),
            _buildInfoRow('来源', log.source.isEmpty ? '-' : log.source),
            _buildInfoRow(
              '仓库',
              log.repositoryId.isEmpty ? '-' : log.repositoryId,
            ),
            if (log.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('详情', style: AppStyles.textStyleButton),
              SelectableText(log.details, style: AppStyles.textStyleBody),
            ],
            if (log.context.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('上下文', style: AppStyles.textStyleButton),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(log.context),
                style: AppStyles.textStyleCaption,
              ),
            ],
            if (log.stackTrace.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '堆栈',
                style: AppStyles.textStyleButton.copyWith(
                  color: AppStyles.errorColor,
                ),
              ),
              SelectableText(
                log.stackTrace,
                style: AppStyles.textStyleCaption.copyWith(
                  color: AppStyles.errorColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: AppStyles.textStyleBody),
          ),
          Expanded(
            child: SelectableText(value, style: AppStyles.textStyleBody),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _palette(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return (FluentIcons.bug, AppStyles.infoColor);
      case AppLogLevel.info:
        return (FluentIcons.info, AppStyles.primaryColor);
      case AppLogLevel.warning:
        return (FluentIcons.warning, AppStyles.warningColor);
      case AppLogLevel.error:
        return (FluentIcons.error_badge, AppStyles.errorColor);
    }
  }

  String _formatTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $hh:$mm:$ss.$ms';
  }

  String _contextText(Map<String, dynamic> context) {
    if (context.isEmpty) {
      return '';
    }
    return context.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(' ');
  }

  Future<void> _clearLogs() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认清空',
      content: '确定要清空所有应用日志吗？此操作不可恢复。',
      isDestructive: true,
    );

    if (!confirmed) {
      return;
    }

    await _appLogService.clearLogs();
    await _loadLogs();
  }
}
