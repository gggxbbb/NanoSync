import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_theme.dart';

class SettingsCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const SettingsCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    if (title != null || icon != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || icon != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: AppStyles.primaryColor),
                    const SizedBox(width: 12),
                  ],
                  if (title != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: theme.typography.subtitle),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppStyles.lightTextSecondary(isDark),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          content,
        ],
      );
    }

    if (onTap != null) {
      content = HoverButton(
        onPressed: onTap,
        builder: (context, states) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppStyles.cardBackground(isDark),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: states.isHovered
                  ? AppStyles.primaryColor.withValues(alpha: 0.3)
                  : AppStyles.borderColor(isDark),
            ),
          ),
          child: content,
        ),
      );
    } else {
      content = Container(
        decoration: BoxDecoration(
          color: AppStyles.cardBackground(isDark),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppStyles.borderColor(isDark)),
        ),
        child: content,
      );
    }

    return content;
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? iconColor;
  final Color? iconBackground;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.iconColor,
    this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: AppStyles.cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    iconBackground ??
                    AppStyles.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor ?? AppStyles.primaryColor),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: AppStyles.lightTextSecondary(isDark),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value ?? '-',
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskCard extends StatelessWidget {
  final String name;
  final String description;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget>? badges;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isRunning;
  final double? progress;

  const TaskCard({
    super.key,
    required this.name,
    required this.description,
    this.leading,
    this.trailing,
    this.badges,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isRunning = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return HoverButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      builder: (context, states) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: AppStyles.hoverCardDecoration(
            isDark,
            states.isHovered,
            isSelected: isSelected,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 16)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.typography.body?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppStyles.lightTextSecondary(isDark),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badges != null && badges!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: badges!),
                    ],
                    if (progress != null && isRunning) ...[
                      const SizedBox(height: 8),
                      ProgressBar(value: progress! * 100),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        );
      },
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppStyles.statusBadgeBackground(color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppStyles.statusBadgeTextColor(color)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppStyles.statusBadgeTextColor(color),
            ),
          ),
        ],
      ),
    );
  }
}
