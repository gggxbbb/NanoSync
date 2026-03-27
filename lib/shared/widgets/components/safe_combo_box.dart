import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_theme.dart';

/// A defensive ComboBox wrapper that avoids fluent_ui ComboBox bugs.
///
/// fluent_ui ComboBox has a known bug with menu geometry calculation.
/// This widget uses DropDownButton as a more stable alternative.
class SafeComboBox<T> extends StatefulWidget {
  const SafeComboBox({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.placeholder,
    this.isExpanded = false,
    this.emptyPlaceholder = '暂无可选项',
  });

  final List<ComboBoxItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final Widget? placeholder;
  final bool isExpanded;
  final String emptyPlaceholder;

  @override
  State<SafeComboBox<T>> createState() => _SafeComboBoxState<T>();
}

class _SafeComboBoxState<T> extends State<SafeComboBox<T>> {
  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (widget.items.isEmpty) {
      // Return a disabled TextBox when no items available
      return TextBox(
        readOnly: true,
        placeholder: widget.emptyPlaceholder,
        style: AppStyles.textStyleBody.copyWith(
          color: AppStyles.lightTextSecondary(isDark),
        ),
      );
    }

    // Find the selected item
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );

    // Use DropDownButton as a stable alternative to ComboBox
    return DropDownButton(
      closeAfterClick: true,
      leading: widget.placeholder,
      title: DefaultTextStyle(
        style: AppStyles.textStyleBody.copyWith(
          color: isDark ? Colors.white : Colors.black,
        ),
        child: selectedItem.child,
      ),
      items: widget.items.map((item) {
        return MenuFlyoutItem(
          leading: item.value == widget.value
              ? Icon(
                  FluentIcons.check_mark,
                  size: 12,
                  color: isDark ? Colors.white : Colors.black,
                )
              : const SizedBox(width: 12),
          text: DefaultTextStyle(
            style: AppStyles.textStyleBody.copyWith(
              color: isDark ? Colors.white : Colors.black,
            ),
            child: item.child,
          ),
          onPressed: () {
            widget.onChanged?.call(item.value);
          },
        );
      }).toList(),
    );
  }
}
