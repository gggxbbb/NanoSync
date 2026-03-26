import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 应用主题配置
class AppTheme extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useMica = true;

  ThemeMode get themeMode => _themeMode;
  bool get useMica => _useMica;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setUseMica(bool value) {
    _useMica = value;
    notifyListeners();
  }

  /// 浅色主题数据
  static FluentThemeData get lightTheme => FluentThemeData(
        brightness: Brightness.light,
        accentColor: Colors.blue,
        navigationPaneTheme: NavigationPaneThemeData(
          backgroundColor: Colors.white,
          highlightColor: Colors.blue,
        ),
      );

  /// 深色主题数据
  static FluentThemeData get darkTheme => FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
        navigationPaneTheme: NavigationPaneThemeData(
          backgroundColor: const Color(0xFF1F1F1F),
          highlightColor: Colors.blue,
        ),
      );
}
