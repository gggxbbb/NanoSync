import 'package:fluent_ui/fluent_ui.dart';

/// 统一样式管理类 - 集中管理所有颜色、样式和主题配置
class AppStyles {
  AppStyles._();

  // ============ 品牌颜色 ============
  static const Color primaryColor = Color(0xFF0067C0);
  static const Color accentColor = Color(0xFF0078D4);
  static const Color successColor = Color(0xFF107C10);
  static const Color warningColor = Color(0xFFFF8C00);
  static const Color errorColor = Color(0xFFD13438);
  static const Color infoColor = Color(0xFF0078D4);

  // ============ 背景颜色 ============
  static const Color lightBackground = Color(0xFFF3F3F3);
  static const Color darkBackground = Color(0xFF202020);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF2D2D2D);
  static const Color lightPane = Color(0xFFF9F9F9);
  static const Color darkPane = Color(0xFF1F1F1F);

  // ============ 文字颜色 ============
  static Color lightTextPrimary(Color? color) => color ?? Colors.black;
  static Color darkTextPrimary(Color? color) => color ?? Colors.white;
  static Color lightTextSecondary(bool isDark) =>
      isDark ? const Color(0xFFB8B8B8) : const Color(0xFF666666);
  static Color lightTextTertiary(bool isDark) =>
      isDark ? const Color(0xFF999999) : const Color(0xFF7A7A7A);

  // ============ 边框颜色 ============
  static Color borderColor(bool isDark) =>
      isDark ? const Color(0xFF404040) : const Color(0xFFE0E0E0);
  static Color dividerColor(bool isDark) =>
      isDark ? const Color(0xFF404040) : const Color(0xFFE5E5E5);
  static Color hoverBorderColor(bool isDark) =>
      isDark ? const Color(0xFF555555) : const Color(0xFFBBBBBB);

  // ============ 下拉框颜色（统一 WinUI 风格） ============
  static Color dropdownDefaultBackground(bool isDark) =>
      isDark ? const Color(0xFF2A2A2A) : Colors.white;
  static Color dropdownHoverBackground(bool isDark) =>
      isDark ? const Color(0xFF383838) : const Color(0xFFF8F8F8);
  static Color dropdownOpenBackground(bool isDark) =>
      isDark ? const Color(0xFF313131) : Colors.white;
  static Color dropdownMenuBackground(bool isDark) =>
      isDark ? const Color(0xFF232323) : Colors.white;
  static Color dropdownHoverBorder(bool isDark) =>
      isDark ? const Color(0xFF5A5A5A) : const Color(0xFF8A8A8A);
  static Color dropdownItemHover(bool isDark) =>
      isDark ? const Color(0xFF404040) : const Color(0xFFF2F2F2);

  // ============ 背景样式 ============
  static Color cardBackground(bool isDark) => isDark
      ? darkCard.withValues(alpha: 0.85)
      : lightCard.withValues(alpha: 0.85);

  static Color hoverBackground(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  static Color pressedBackground(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);

  // ============ 字体设置 ============
  static const String fontFamily = 'Microsoft YaHei UI';

  static TextStyle get textStyleBody => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get textStyleSubtitle => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get textStyleTitle => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get textStyleCaption => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get textStyleButton => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // ============ 状态徽章样式 ============
  static Color statusBadgeBackground(Color color) =>
      color.withValues(alpha: 0.15);

  static Color statusBadgeTextColor(Color color) => color;

  // ============ 卡片装饰 ============
  static BoxDecoration cardDecoration(bool isDark) => BoxDecoration(
    color: cardBackground(isDark),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: borderColor(isDark)),
  );

  static BoxDecoration hoverCardDecoration(
    bool isDark,
    bool isHovered, {
    bool isSelected = false,
  }) => BoxDecoration(
    color: isSelected
        ? primaryColor.withValues(alpha: 0.15)
        : isHovered
        ? hoverBackground(isDark)
        : cardBackground(isDark),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: isSelected
          ? primaryColor
          : isHovered
          ? primaryColor.withValues(alpha: 0.3)
          : borderColor(isDark),
    ),
  );

  // ============ 图标颜色 ============
  static Color iconColor(bool isDark, {Color? customColor}) =>
      customColor ?? lightTextSecondary(isDark);

  static Color iconColorPrimary() => primaryColor;

  // ============ Fluent 主题 ============
  static AccentColor get fluentAccentColor => AccentColor.swatch({
    'darkest': const Color(0xFF004A7C),
    'darker': const Color(0xFF005A97),
    'dark': const Color(0xFF0067C0),
    'normal': const Color(0xFF0078D4),
    'light': const Color(0xFF2B88D8),
    'lighter': const Color(0xFF429CE3),
    'lightest': const Color(0xFF6CB6EE),
  });

  static FluentThemeData get lightTheme => FluentThemeData(
    brightness: Brightness.light,
    accentColor: fluentAccentColor,
    scaffoldBackgroundColor: Colors.transparent,
    cardColor: cardBackground(false),
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: Colors.transparent,
      overlayBackgroundColor: Colors.transparent,
      highlightColor: primaryColor,
    ),
    menuColor: lightCard,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: lightCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor(false)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: textStyleCaption.copyWith(color: Colors.black),
    ),
  );

  static FluentThemeData get darkTheme => FluentThemeData(
    brightness: Brightness.dark,
    accentColor: fluentAccentColor,
    scaffoldBackgroundColor: Colors.transparent,
    cardColor: cardBackground(true),
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: Colors.transparent,
      overlayBackgroundColor: Colors.transparent,
      highlightColor: primaryColor,
    ),
    menuColor: darkCard,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: darkCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor(true)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: textStyleCaption.copyWith(color: Colors.white),
    ),
  );
}

/// 主题管理器 - 管理深色/浅色切换
class ThemeManager extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useMica = true;

  ThemeMode get themeMode => _themeMode;
  bool get useMica => _useMica;

  bool isDark(BuildContext context) {
    return _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  void setUseMica(bool value) {
    if (_useMica != value) {
      _useMica = value;
      notifyListeners();
    }
  }

  void toggleTheme() {
    setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
