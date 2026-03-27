import 'package:fluent_ui/fluent_ui.dart';
import '../../../data/services/vc_engine.dart';

class DiffViewer extends StatefulWidget {
  final List<VcFileDiff> diffs;
  final bool initialSideBySide;

  const DiffViewer({
    super.key,
    required this.diffs,
    this.initialSideBySide = false,
  });

  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  late bool _sideBySide;

  @override
  void initState() {
    super.initState();
    _sideBySide = widget.initialSideBySide;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.diffs.isEmpty) {
      return const Center(child: Text('无可显示的差异'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: widget.diffs.length,
            itemBuilder: (context, index) {
              final diff = widget.diffs[index];
              return _buildFileDiffCard(diff);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Text('共 ${widget.diffs.length} 个文件差异'),
        const Spacer(),
        Text(_sideBySide ? '并排模式' : '统一模式'),
        const SizedBox(width: 8),
        ToggleSwitch(
          checked: _sideBySide,
          onChanged: (value) => setState(() => _sideBySide = value),
        ),
      ],
    );
  }

  Widget _buildFileDiffCard(VcFileDiff diff) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    diff.relativePath,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '+${diff.additions} -${diff.deletions}',
                  style: TextStyle(color: Colors.grey[110]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (diff.isBinary)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[80]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('二进制文件，暂不支持文本差异预览'),
              )
            else if (_sideBySide)
              _buildSideBySideDiff(diff)
            else
              _buildUnifiedDiff(diff),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedDiff(VcFileDiff diff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final hunk in diff.hunks) ...[
          Container(
            color: Colors.grey[30],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@',
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
          for (final line in hunk.lines) _buildUnifiedLine(line),
        ],
      ],
    );
  }

  Widget _buildUnifiedLine(VcDiffLine line) {
    return Container(
      color: _lineBackgroundColor(line.type),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              line.oldLineNumber > 0 ? '${line.oldLineNumber}' : '',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Consolas', color: Colors.grey[110]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              line.newLineNumber > 0 ? '${line.newLineNumber}' : '',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Consolas', color: Colors.grey[110]),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 16,
            child: Text(
              _linePrefix(line.type),
              style: TextStyle(fontFamily: 'Consolas', color: Colors.grey[120]),
            ),
          ),
          Expanded(
            child: SelectableText(
              line.content,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBySideDiff(VcFileDiff diff) {
    final rows = <_SideBySideRow>[];

    for (final hunk in diff.hunks) {
      rows.add(_SideBySideRow.hunk(hunk));
      for (final line in hunk.lines) {
        if (line.type == 'add') {
          rows.add(_SideBySideRow(right: line));
        } else if (line.type == 'delete') {
          rows.add(_SideBySideRow(left: line));
        } else {
          rows.add(_SideBySideRow(left: line, right: line));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.map(_buildSideBySideRow).toList(),
    );
  }

  Widget _buildSideBySideRow(_SideBySideRow row) {
    if (row.hunk != null) {
      final h = row.hunk!;
      return Container(
        color: Colors.grey[30],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '@@ -${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@',
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildSideCell(row.left, isLeft: true)),
        Container(width: 1, color: Colors.grey[70]),
        Expanded(child: _buildSideCell(row.right, isLeft: false)),
      ],
    );
  }

  Widget _buildSideCell(VcDiffLine? line, {required bool isLeft}) {
    if (line == null) {
      return Container(height: 22, color: Colors.transparent);
    }

    final lineNumber = isLeft ? line.oldLineNumber : line.newLineNumber;

    return Container(
      color: _lineBackgroundColor(line.type),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              lineNumber > 0 ? '$lineNumber' : '',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Consolas', color: Colors.grey[110]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              line.content,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Color _lineBackgroundColor(String type) {
    switch (type) {
      case 'add':
        return Colors.green.withAlpha(20);
      case 'delete':
        return Colors.red.withAlpha(20);
      default:
        return Colors.transparent;
    }
  }

  String _linePrefix(String type) {
    switch (type) {
      case 'add':
        return '+';
      case 'delete':
        return '-';
      default:
        return ' ';
    }
  }
}

class _SideBySideRow {
  final VcDiffHunk? hunk;
  final VcDiffLine? left;
  final VcDiffLine? right;

  const _SideBySideRow({this.left, this.right}) : hunk = null;

  const _SideBySideRow.hunk(VcDiffHunk h) : hunk = h, left = null, right = null;
}
