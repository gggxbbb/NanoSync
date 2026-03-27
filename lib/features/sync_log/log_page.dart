import '../../core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../data/models/sync_log.dart';
import '../../data/services/vc_sync_service.dart';
import '../../shared/widgets/components/indicators.dart';
import '../../shared/widgets/components/dialogs.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final VcSyncService _vcSync = VcSyncService();
  List<SyncLog> _logs = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await _vcSync.getAllSyncLogs();
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  List<SyncLog> get _filteredLogs {
    if (_searchQuery.isEmpty) return _logs;
    return _logs.where((l) {
      final name = l.repositoryName.isEmpty ? '已删除的仓库' : l.repositoryName;
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          '同步日志',
          style: AppStyles.textStyleTitle.copyWith(color: primaryTextColor),
        ),
        commandBar: Align(
          alignment: Alignment.centerRight,
          child: CommandBar(
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                label: Text(
                  '刷新',
                  style: AppStyles.textStyleButton.copyWith(
                    color: primaryTextColor,
                  ),
                ),
                onPressed: _loadLogs,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.delete),
                label: Text(
                  '清空',
                  style: AppStyles.textStyleButton.copyWith(
                    color: primaryTextColor,
                  ),
                ),
                onPressed: _clearLogs,
              ),
            ],
          ),
        ),
      ),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextBox(
              placeholder: '搜索日志...',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 16),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: ProgressRing())
                : _filteredLogs.isEmpty
                ? const EmptyState(
                    icon: FluentIcons.list,
                    title: '暂无日志',
                    subtitle: '执行同步任务后日志将显示在这里',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) =>
                        _buildLogCard(_filteredLogs[index], isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(SyncLog log, bool isDark) {
    final isSuccess = log.status == 'success';
    final isFailed = log.status == 'failed';
    final color = isSuccess
        ? AppStyles.successColor
        : isFailed
        ? AppStyles.errorColor
        : AppStyles.infoColor;
    final bgColor = isDark
        ? AppStyles.darkCard.withValues(alpha: 0.85)
        : AppStyles.lightCard.withValues(alpha: 0.85);
    final taskName = log.repositoryName.isEmpty ? '已删除的仓库' : log.repositoryName;
    final isDeleted = log.repositoryName.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppStyles.borderColor(isDark)),
      ),
      child: Expander(
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSuccess
                ? FluentIcons.check_mark
                : isFailed
                ? FluentIcons.error_badge
                : FluentIcons.clock,
            color: color,
            size: 16,
          ),
        ),
        header: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          taskName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontStyle: isDeleted
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: isDeleted
                                ? (isDark ? Colors.grey[100] : Colors.grey[140])
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDeleted) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppStyles.warningColor.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '已删除',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppStyles.warningColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${_formatTime(log.startTime)} | ${isSuccess
                        ? '成功'
                        : isFailed
                        ? '失败'
                        : '进行中'} | 成功: ${log.successCount} 失败: ${log.failCount}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[100] : Colors.grey[140],
                    ),
                  ),
                  if (log.sourceDeviceName.isNotEmpty ||
                      log.sourceUsername.isNotEmpty)
                    Text(
                      '来源: ${log.sourceDeviceName.isEmpty ? '-' : log.sourceDeviceName} / ${log.sourceUsername.isEmpty ? '-' : log.sourceUsername}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[100] : Colors.grey[140],
                      ),
                    ),
                ],
              ),
            ),
            if (!isDeleted)
              Tooltip(
                message: '仓库同步请在“仓库”页面执行',
                child: Icon(
                  FluentIcons.sync,
                  size: 14,
                  color: AppStyles.primaryColor,
                ),
              ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('开始时间', _formatTime(log.startTime)),
            _buildInfoRow(
              '结束时间',
              log.endTime != null ? _formatTime(log.endTime!) : '进行中',
            ),
            _buildInfoRow('总耗时', log.durationText),
            _buildInfoRow('总文件数', log.totalFiles.toString()),
            _buildInfoRow('成功', log.successCount.toString()),
            _buildInfoRow('失败', log.failCount.toString()),
            _buildInfoRow('跳过', log.skipCount.toString()),
            if (log.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '错误信息:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppStyles.errorColor,
                ),
              ),
              Text(
                log.errorMessage!,
                style: TextStyle(color: AppStyles.errorColor),
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
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[120])),
          ),
          Text(value),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _clearLogs() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认清空',
      content: '确定要清空所有同步日志吗？此操作不可恢复。',
      isDestructive: true,
    );
    if (confirmed) {
      await _vcSync.clearAllSyncLogs();
      _loadLogs();
    }
  }
}
