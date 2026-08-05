import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/ai_recognition_settings_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/screens/home_screen.dart';
import 'package:openlogtool/services/app_logger.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/services/app_fonts.dart';
import 'package:openlogtool/services/key_value_store.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/utils/windows_accessibility_guard.dart';
import 'package:openlogtool/bootstrap/rust_library_loader.dart';
import 'package:openlogtool/src/bridge/frb_generated.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();
  FlutterError.onError = (details) {
    AppLogger.instance.error('Flutter error', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.error('Platform error', error, stack);
    return true;
  };
  try {
    await loadAppFonts();
  } catch (e) {
    debugPrint('Failed to load app fonts, falling back to system fonts: $e');
  }

  // 桌面子窗口只渲染主控屏，不初始化 Rust、本地数据库或主应用 Provider。
  final controllerWindow =
      await ControllerWindowService.currentWindowLaunch(args);
  if (controllerWindow != null) {
    runApp(
      WindowsAccessibilityCrashGuard(
        child: ControllerDisplayWindowApp(session: controllerWindow),
      ),
    );
    return;
  }

  // Always use the Rust library shipped with this application. The generated
  // desktop fallback is relative to the process working directory and can
  // otherwise pick up a stale library from the source tree.
  await RustLib.init(externalLibrary: bundledRustLibrary());

  String dbPath;
  if (kIsWeb) {
    dbPath = 'openlogtool_rust.db';
  } else {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      dbPath = p.join(dir.path, 'openlogtool_rust.db');
    } catch (e) {
      dbPath = 'openlogtool_rust.db';
    }
  }
  try {
    await RustApi.init(dbPath: dbPath);
  } catch (e) {
    debugPrint('Rust DB init: $e');
  }

  // Web：把 localStorage（SharedPreferences）旧数据一次性拷贝到 IndexedDB。
  // 桌面端无需迁移，直接使用 SharedPreferences。
  // 首次启动等待迁移完成，避免 provider 先读 IndexedDB 读到默认值。
  if (kIsWeb) {
    await migrateLegacyLocalStorage(await openKeyValueStore());
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppInfoProvider()..loadAppInfo()),
        ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AiRecognitionSettingsProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ChangeNotifierProvider(create: (_) => LogProvider()),
        ChangeNotifierProxyProvider3<ServerProvider, SessionProvider,
            LogProvider, CollaborationProvider>(
          create: (_) => CollaborationProvider(),
          update: (_, server, sessions, logs, previous) =>
              (previous ?? CollaborationProvider())
                ..updateDependencies(server, sessions, logs),
        ),
        ChangeNotifierProxyProvider5<
            ServerProvider,
            SessionProvider,
            LogProvider,
            CollaborationProvider,
            DictionaryProvider,
            PersonalCloudProvider>(
          create: (_) => PersonalCloudProvider(),
          update: (_, server, sessions, logs, collaboration, dictionaries,
                  previous) =>
              (previous ?? PersonalCloudProvider())
                ..updateDependencies(
                  server,
                  sessions,
                  logs,
                  collaboration,
                  dictionaries,
                ),
        ),
      ],
      child: const WindowsAccessibilityCrashGuard(child: MyApp()),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.select<SettingsProvider,
        ({Color color, bool dark, String? fontFamily, Locale? locale})>(
      (settings) => (
        color: settings.themeColor,
        dark: settings.isDarkMode,
        fontFamily: settings.fontFamily,
        locale: settings.locale,
      ),
    );

    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: appearance.locale,
      localeResolutionCallback: resolveAppLocale,
      theme: buildAppTheme(
        brightness: Brightness.light,
        seedColor: appearance.color,
        fontFamily: appearance.fontFamily,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        seedColor: appearance.color,
        fontFamily: appearance.fontFamily,
      ),
      themeMode: appearance.dark ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
