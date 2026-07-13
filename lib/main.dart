import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/screens/home_screen.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/src/bridge/frb_generated.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

ExternalLibrary? _bundledRustLibrary() {
  if (kIsWeb) return null;

  if (Platform.isAndroid) {
    return ExternalLibrary.open('libopenlogtool_core.so');
  }

  final executableDirectory = p.dirname(Platform.resolvedExecutable);
  final libraryPath = switch (Platform.operatingSystem) {
    'linux' => p.join(
        executableDirectory,
        'lib',
        'libopenlogtool_core.so',
      ),
    'windows' => p.join(executableDirectory, 'openlogtool_core.dll'),
    'macos' => p.normalize(
        p.join(
          executableDirectory,
          '..',
          'Frameworks',
          'libopenlogtool_core.dylib',
        ),
      ),
    _ => throw UnsupportedError(
        'OpenLogTool does not bundle a Rust core for '
        '${Platform.operatingSystem}.',
      ),
  };
  if (!File(libraryPath).existsSync()) {
    throw StateError('Bundled Rust core is missing: $libraryPath');
  }
  return ExternalLibrary.open(libraryPath);
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面子窗口只渲染主控屏，不初始化 Rust、本地数据库或主应用 Provider。
  final controllerWindow =
      await ControllerWindowService.currentWindowLaunch(args);
  if (controllerWindow != null) {
    runApp(ControllerDisplayWindowApp(session: controllerWindow));
    return;
  }

  // Always use the Rust library shipped with this application. The generated
  // desktop fallback is relative to the process working directory and can
  // otherwise pick up a stale library from the source tree.
  await RustLib.init(externalLibrary: _bundledRustLibrary());

  String dbPath;
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    dbPath = p.join(dir.path, 'openlogtool_rust.db');
  } catch (e) {
    dbPath = 'openlogtool_rust.db';
  }
  try {
    await RustApi.init(dbPath: dbPath);
  } catch (e) {
    debugPrint('Rust DB init: $e');
  }

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWebBasicWebWorker;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppInfoProvider()..loadAppInfo()),
        ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.select<SettingsProvider,
        ({Color color, bool dark, String? fontFamily})>(
      (settings) => (
        color: settings.themeColor,
        dark: settings.isDarkMode,
        fontFamily: settings.fontFamily,
      ),
    );

    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
