import 'package:fluent_ui/fluent_ui.dart' hide ComboBoxItem;
import '../../../core/theme/app_theme.dart';

/// Custom ComboBoxItem that wraps a value with a display widget
class ComboBoxItem<T> {
  const ComboBoxItem({required this.value, required this.child});

  final T value;
  final Widget child;
}

/// A styled dropdown selector widget with consistent appearance across the app.
///
/// This widget provides a unified dropdown experience that matches the app's
/// design system, with proper theming for both light and dark modes.
class StyledDropdown<T> extends StatefulWidget {
  const StyledDropdown({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.placeholder,
    this.isExpanded = false,
    this.emptyPlaceholder = '暂无可选项',
    this.label,
  });

  final List<DropdownItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final Widget? placeholder;
  final bool isExpanded;
  final String emptyPlaceholder;
  final String? label;

  @override
  State<StyledDropdown<T>> createState() => _StyledDropdownState<T>();
}

class _StyledDropdownState<T> extends State<StyledDropdown<T>> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.items.isEmpty) {
      return _buildEmptyState(isDark);
    }

    // Find the selected item
    final selectedItem = widget.items.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => widget.items.first,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppStyles.textStyleCaption.copyWith(
              color: AppStyles.lightTextSecondary(isDark),
            ),
          ),
          const SizedBox(height: 4),
        ],
        _buildDropdownButton(theme, isDark, selectedItem),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[80] : Colors.grey[20],
        border: Border.all(color: AppStyles.borderColor(isDark)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.emptyPlaceholder,
              style: AppStyles.textStyleBody.copyWith(
                color: AppStyles.lightTextSecondary(isDark),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownButton(
    FluentThemeData theme,
    bool isDark,
    DropdownItem<T> selectedItem,
  ) {
    final borderColor = _isOpen
        ? theme.accentColor
        : AppStyles.borderColor(isDark);
    final backgroundColor = isDark ? Colors.grey[80] : Colors.white;

    return GestureDetector(
      onTap: widget.onChanged != null ? () => _showDropdown(context) : null,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (widget.placeholder != null) ...[
              widget.placeholder!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: AppStyles.textStyleBody.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                ),
                child: selectedItem.label ?? Text(selectedItem.displayText),
              ),
            ),
            Icon(
              _isOpen ? FluentIcons.chevron_up : FluentIcons.chevron_down,
              size: 12,
              color: AppStyles.lightTextSecondary(isDark),
            ),
          ],
        ),
      ),
    );
  }

  void _showDropdown(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    setState(() => _isOpen = true);

    final menuItems = widget.items.map((item) {
      return _DropdownMenuItem<T>(
        item: item,
        isSelected: item.value == widget.value,
        onTap: () {
          Navigator.pop(context);
          setState(() => _isOpen = false);
          widget.onChanged?.call(item.value);
        },
      );
    }).toList();

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              width: size.width,
              child: _DropdownMenu(items: menuItems),
            ),
            // Invisible barrier to detect outside clicks
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _isOpen = false);
                },
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isOpen = false);
      }
    });
  }
}

/// Dropdown item for StyledDropdown
class DropdownItem<T> {
  const DropdownItem({required this.value, this.label, this.displayText = ''});

  final T value;
  final Widget? label;
  final String displayText;
}

class _DropdownMenuItem<T> extends StatelessWidget {
  const _DropdownMenuItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final DropdownItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.accentColor.withAlpha(30)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (isSelected)
                Icon(FluentIcons.check_mark, size: 12, color: theme.accentColor)
              else
                const SizedBox(width: 12),
              const SizedBox(width: 8),
              Expanded(
                child: DefaultTextStyle(
                  style: AppStyles.textStyleBody.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  child: item.label ?? Text(item.displayText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownMenu extends StatelessWidget {
  const _DropdownMenu({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[90] : Colors.white;

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: AppStyles.borderColor(isDark)),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}

/// A defensive ComboBox wrapper that avoids fluent_ui ComboBox bugs.
///
/// fluent_ui ComboBox has a known bug with menu geometry calculation.
/// This widget uses a custom dropdown implementation as a stable alternative.
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
  bool _isOpen = false;
  bool _isHovering = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.items.isEmpty) {
      return _buildEmptyState(isDark);
    }

    final hasSelectedValue =
        widget.value != null &&
        widget.items.any((item) => item.value == widget.value);
    final selectedItem = hasSelectedValue
        ? widget.items.firstWhere((item) => item.value == widget.value)
        : null;

    return _buildDropdownButton(theme, isDark, selectedItem);
  }

  Widget _buildEmptyState(bool isDark) {
    final emptyBackground = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF3F3F3);
    final iconAreaBackground = isDark
        ? const Color(0xFF242424)
        : const Color(0xFFF0F0F0);

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: emptyBackground,
        border: Border.all(color: AppStyles.borderColor(isDark), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                widget.emptyPlaceholder,
                style: AppStyles.textStyleBody.copyWith(
                  color: AppStyles.lightTextSecondary(isDark),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Container(
            width: 30,
            decoration: BoxDecoration(
              color: iconAreaBackground,
              border: Border(
                left: BorderSide(color: AppStyles.borderColor(isDark)),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              FluentIcons.chevron_down_small,
              size: 9,
              color: AppStyles.lightTextSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownButton(
    FluentThemeData theme,
    bool isDark,
    ComboBoxItem<T>? selectedItem,
  ) {
    final hoverBorder = AppStyles.dropdownHoverBorder(isDark);
    final openBackground = AppStyles.dropdownOpenBackground(isDark);
    final hoverBackground = AppStyles.dropdownHoverBackground(isDark);
    final defaultBackground = AppStyles.dropdownDefaultBackground(isDark);
    final activeBorder = AppStyles.accentColor;

    final borderColor = (_isOpen || _isFocused)
        ? activeBorder
        : _isHovering
        ? hoverBorder
        : AppStyles.borderColor(isDark);
    final backgroundColor = _isPressed
        ? (isDark ? const Color(0xFF222222) : const Color(0xFFEDEDED))
        : _isOpen
        ? openBackground
        : _isHovering
        ? hoverBackground
        : defaultBackground;
    final iconAreaBackground = _isPressed
        ? (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8))
        : _isOpen
        ? (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F3F3))
        : _isHovering
        ? (isDark ? const Color(0xFF333333) : const Color(0xFFF2F2F2))
        : (isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F5));

    return FocusableActionDetector(
      enabled: widget.onChanged != null,
      mouseCursor: widget.onChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (focused) {
        if (mounted) {
          setState(() => _isFocused = focused);
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Listener(
          onPointerDown: widget.onChanged == null
              ? null
              : (_) => setState(() => _isPressed = true),
          onPointerUp: widget.onChanged == null
              ? null
              : (_) => setState(() => _isPressed = false),
          onPointerCancel: widget.onChanged == null
              ? null
              : (_) => setState(() => _isPressed = false),
          child: GestureDetector(
            onTap: widget.onChanged != null
                ? () => _showDropdown(context)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              height: 32,
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border.all(
                  color: borderColor,
                  width: (_isOpen || _isFocused) ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: DefaultTextStyle(
                        style: AppStyles.textStyleBody.copyWith(
                          color: selectedItem == null
                              ? AppStyles.lightTextSecondary(isDark)
                              : (isDark ? Colors.white : Colors.black),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child:
                            selectedItem?.child ??
                            widget.placeholder ??
                            Text(widget.emptyPlaceholder),
                      ),
                    ),
                  ),
                  Container(
                    width: 30,
                    decoration: BoxDecoration(
                      color: iconAreaBackground,
                      border: Border(
                        left: BorderSide(color: AppStyles.borderColor(isDark)),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _isOpen
                          ? FluentIcons.chevron_up_small
                          : FluentIcons.chevron_down_small,
                      size: 9,
                      color: AppStyles.lightTextSecondary(isDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDropdown(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    setState(() => _isOpen = true);

    final menuItems = widget.items.map((item) {
      return _SafeComboBoxMenuItem<T>(
        item: item,
        isSelected: item.value == widget.value,
        onTap: () {
          Navigator.pop(context);
          setState(() => _isOpen = false);
          widget.onChanged?.call(item.value);
        },
      );
    }).toList();

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _isOpen = false);
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              width: size.width,
              child: _SafeComboBoxMenu(items: menuItems),
            ),
          ],
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isOpen = false);
      }
    });
  }
}

class _SafeComboBoxMenuItem<T> extends StatelessWidget {
  const _SafeComboBoxMenuItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final ComboBoxItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    const selectionColor = AppStyles.accentColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: HoverButton(
        onPressed: onTap,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          final color = isSelected
              ? selectionColor.withAlpha(35)
              : hovered
              ? AppStyles.dropdownItemHover(isDark)
              : Colors.transparent;

          return Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: color),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: isSelected
                      ? Icon(
                          FluentIcons.check_mark,
                          size: 10,
                          color: selectionColor,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DefaultTextStyle(
                    style: AppStyles.textStyleBody.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: item.child,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SafeComboBoxMenu extends StatelessWidget {
  const _SafeComboBoxMenu({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final backgroundColor = AppStyles.dropdownMenuBackground(isDark);

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: AppStyles.borderColor(isDark), width: 1),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 60 : 28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}
