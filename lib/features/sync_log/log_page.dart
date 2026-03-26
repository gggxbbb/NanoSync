import 'package:fluent_ui/fluent_ui.dart';
import '../../data/models/sync_log.dart';
import '../../data/database/database_helper.dart';

/// 同步日志页面
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;
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
    final maps = await _db.getAllLogs();
    setState(() {
      _logs = maps.map((m) => SyncLog.fromMap(m)).toList();
      _loading = false;
    });
  }

  List<SyncLog> get _filteredLogs {
    if (_searchQuery.isEmpty) return _logs;
    return _logs
        .where((l) =>
            l.taskName.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('同步日志'),
        commandBar: CommandBar(
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
                    ? const Center(child: Text('暂无同步日志'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = _filteredLogs[index];
                          return _buildLogCard(log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(SyncLog log) {
    final isSuccess = log.status == 'success';
    final isFailed = log.status == 'failed';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Expander(
        leading: Icon(
          isSuccess
              ? FluentIcons.check_mark
              : isFailed
                  ? FluentIcons.error
                  : FluentIcons.clock,
          color: isSuccess
              ? Colors.green
              : isFailed
                  ? Colors.red
                  : Colors.grey,
        ),
        header: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.taskName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${_formatTime(log.startTime)} | ${log.status == 'success' ? '成功' : log.status == 'failed' ? '失败' : '进行中'} | '
                    '成功: ${log.successCount} 失败: ${log.failCount} 跳过: ${log.skipCount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('开始时间', _formatTime(log.startTime)),
            _buildInfoRow('结束时间',
                log.endTime != null ? _formatTime(log.endTime!) : '进行中'),
            _buildInfoRow('总耗时', log.durationText),
            _buildInfoRow('总文件数', log.totalFiles.toString()),
            _buildInfoRow('成功', log.successCount.toString()),
            _buildInfoRow('失败', log.failCount.toString()),
            _buildInfoRow('跳过', log.skipCount.toString()),
            _buildInfoRow('冲突', log.conflictCount.toString()),
            if (log.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text('错误信息:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              Text(log.errorMessage!, style: TextStyle(color: Colors.red)),
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
              child: Text(label, style: TextStyle(color: Colors.grey))),
          Text(value),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有同步日志吗？此操作不可恢复。'),
        actions: [
          Button(
              child: const Text('取消'), onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('清空'),
            onPressed: () {
              _db.clearAllLogs();
              _loadLogs();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
