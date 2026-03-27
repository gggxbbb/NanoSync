import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/vc_engine.dart';
import '../../../shared/widgets/components/cards.dart';

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
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (widget.diffs.isEmpty) {
      return Center(
        child: Text(
          '无可显示的差异',
          style: AppStyles.textStyleBody.copyWith(
            color: AppStyles.lightTextSecondary(isDark),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(isDark),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: widget.diffs.length,
            itemBuilder: (context, index) {
              final diff = widget.diffs[index];
              return _buildFileDiffCard(diff, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Row(
      children: [
        Text(
          '共 ${widget.diffs.length} 个文件差异',
          style: AppStyles.textStyleBody.copyWith(
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const Spacer(),
        Text(
          _sideBySide ? '并排模式' : '统一模式',
          style: AppStyles.textStyleBody.copyWith(
            color: AppStyles.lightTextSecondary(isDark),
          ),
        ),
        const SizedBox(width: 8),
        ToggleSwitch(
          checked: _sideBySide,
          onChanged: (value) => setState(() => _sideBySide = value),
        ),
      ],
    );
  }

  Widget _buildFileDiffCard(VcFileDiff diff, bool isDark) {
    return AppCardSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  diff.relativePath,
                  style: AppStyles.textStyleButton.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Text(
                '+${diff.additions} -${diff.deletions}',
                style: AppStyles.textStyleCaption.copyWith(
                  color: AppStyles.lightTextSecondary(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (diff.isBinary)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppStyles.borderColor(isDark)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '二进制文件，暂不支持文本差异预览',
                style: AppStyles.textStyleBody.copyWith(
                  color: AppStyles.lightTextSecondary(isDark),
                ),
              ),
            )
          else if (_sideBySide)
            _buildSideBySideDiff(diff, isDark)
          else
            _buildUnifiedDiff(diff, isDark),
        ],
      ),
    );
  }

  Widget _buildUnifiedDiff(VcFileDiff diff, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final hunk in diff.hunks) ...[
          Container(
            color: isDark ? Colors.grey[80] : Colors.grey[30],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: isDark ? Colors.grey[100] : Colors.grey[130],
              ),
            ),
          ),
          for (final line in hunk.lines) _buildUnifiedLine(line, isDark),
        ],
      ],
    );
  }

  Widget _buildUnifiedLine(VcDiffLine line, bool isDark) {
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
              style: TextStyle(
                fontFamily: 'Consolas',
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              line.newLineNumber > 0 ? '${line.newLineNumber}' : '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Consolas',
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 16,
            child: Text(
              _linePrefix(line.type),
              style: TextStyle(
                fontFamily: 'Consolas',
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              line.content,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBySideDiff(VcFileDiff diff, bool isDark) {
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
      children: rows.map((row) => _buildSideBySideRow(row, isDark)).toList(),
    );
  }

  Widget _buildSideBySideRow(_SideBySideRow row, bool isDark) {
    if (row.hunk != null) {
      final h = row.hunk!;
      return Container(
        color: isDark ? Colors.grey[80] : Colors.grey[30],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '@@ -${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@',
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 12,
            color: isDark ? Colors.grey[100] : Colors.grey[130],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildSideCell(row.left, isLeft: true, isDark: isDark)),
        Container(width: 1, color: AppStyles.borderColor(isDark)),
        Expanded(
          child: _buildSideCell(row.right, isLeft: false, isDark: isDark),
        ),
      ],
    );
  }

  Widget _buildSideCell(
    VcDiffLine? line, {
    required bool isLeft,
    required bool isDark,
  }) {
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
              style: TextStyle(
                fontFamily: 'Consolas',
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              line.content,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black,
              ),
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
