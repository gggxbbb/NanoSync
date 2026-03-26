import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/task_provider.dart';
import 'shared/widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  // 初始化窗口效果（Mica）
  await Window.initialize();

  // 配置窗口
  final windowOptions = WindowOptions(
    size: const Size(1280, 800),
    minimumSize: const Size(960, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // 隐藏系统标题栏
    title: 'NanoSync',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 初始化SQLite FFI
  sqfliteFfiInit();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppTheme()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: const NanoSyncApp(),
    ),
  );
}

class NanoSyncApp extends StatelessWidget {
  const NanoSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();

    return FluentApp(
      title: 'NanoSync',
      debugShowCheckedModeBanner: false,
      themeMode: theme.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}
