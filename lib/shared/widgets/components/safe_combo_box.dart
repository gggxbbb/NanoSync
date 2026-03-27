import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_theme.dart';

/// A defensive ComboBox wrapper that avoids opening an empty popup.
///
/// fluent_ui ComboBox may throw when items are empty and the popup tries to
/// compute menu geometry. This widget renders a disabled TextBox in that case.
class SafeComboBox<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (items.isEmpty) {
      return ComboBox<T>(
        value: null,
        isExpanded: isExpanded,
        placeholder:
            placeholder ??
            Text(
              emptyPlaceholder,
              style: AppStyles.textStyleBody.copyWith(
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
        items: const [],
        onChanged: null,
      );
    }

    final safeValue = items.any((item) => item.value == value) ? value : null;

    return ComboBox<T>(
      value: safeValue,
      isExpanded: isExpanded,
      placeholder: placeholder,
      items: items,
      onChanged: onChanged,
    );
  }
}
