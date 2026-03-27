import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'data/vc_database.dart';
import 'shared/providers/vc_repository_provider.dart';
import 'shared/widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  await Window.initialize();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'NanoSync',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  sqfliteFfiInit();

  // Pre-initialize version control database to ensure schema is ready.
  await VcDatabase.instance.database;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        ChangeNotifierProvider(create: (_) => VcRepositoryProvider()),
      ],
      child: const NanoSyncApp(),
    ),
  );
}

class NanoSyncApp extends StatelessWidget {
  const NanoSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeManager>();

    return FluentApp(
      title: 'NanoSync',
      debugShowCheckedModeBanner: false,
      themeMode: theme.themeMode,
      theme: AppStyles.lightTheme,
      darkTheme: AppStyles.darkTheme,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      home: const AppShell(),
    );
  }
}
