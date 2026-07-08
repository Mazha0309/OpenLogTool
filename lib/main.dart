import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/providers/sync_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/rust_log_provider.dart';
import 'package:openlogtool/providers/rust_session_provider.dart';
import 'package:openlogtool/providers/rust_dict_provider.dart';
import 'package:openlogtool/providers/rust_settings_provider.dart';
import 'package:openlogtool/screens/rust_home_screen.dart' as rust;
import 'package:openlogtool/src/theme/app_theme.dart';
import 'package:openlogtool/src/bridge/frb_generated.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/providers/rust_settings_provider.dart';
import 'dart:io' as io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io' as io;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  String dbPath;
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    dbPath = p.join(dir.path, 'openlogtool_rust.db');
    debugPrint('Rust DB path: $dbPath');
  } catch (e) {
    debugPrint('Failed to get support dir: $e, using fallback');
    dbPath = p.join(io.Directory.current.path, 'openlogtool_rust.db');
  }
  try {
    await RustApi.init(dbPath: dbPath);
    debugPrint('Rust DB initialized: $dbPath');
  } catch (e) {
    debugPrint('Rust DB init error: $e');
  }

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWebBasicWebWorker;
  } else if (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        // Existing providers (kept for backward compatibility)
        ChangeNotifierProvider(create: (_) => AppInfoProvider()..loadAppInfo()),
        ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProxyProvider<SyncProvider, DictionaryProvider>(
          create: (_) => DictionaryProvider(),
          update: (_, syncProvider, dictionaryProvider) {
            final provider = dictionaryProvider ?? DictionaryProvider();
            provider.setOnDictionaryChanged(() async {
              if (syncProvider.settings.syncEnabled &&
                  syncProvider.settings.syncMode == 'realtime') {
                await syncProvider.triggerSyncAndWait();
              }
            });
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<SyncProvider, LogProvider>(
          create: (_) => LogProvider(),
          update: (context, syncProvider, logProvider) {
            final provider = logProvider ?? LogProvider();
            provider.setOnDataChanged(() async {
              if (syncProvider.settings.syncEnabled &&
                  syncProvider.settings.syncMode == 'realtime') {
                await syncProvider.triggerSyncAndWait();
              }
            });
            provider.setOnLogChanged((log, isDelete) async {
              final sp = Provider.of<SyncProvider>(context, listen: false);
              final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
              if (sp.settings.syncEnabled && sessionProvider.currentSessionId != null) {
                if (isDelete) {
                  await sp.pushLogDeleteToCollab(
                    sessionProvider.currentSessionId!,
                    log.id,
                  );
                } else {
                  await sp.pushLogUpsertToCollab(
                    sessionProvider.currentSessionId!,
                    log.toJson(),
                  );
                }
              }
            });
            return provider;
          },
        ),
        // Rust providers (for new UI)
        ChangeNotifierProvider(create: (_) => RustLogProvider()),
        ChangeNotifierProvider(create: (_) => RustSessionProvider()),
        ChangeNotifierProvider(create: (_) => RustDictProvider()),
        ChangeNotifierProvider(create: (_) => RustSettingsProvider()..load()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<RustSettingsProvider>(context);
    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: sp.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const rust.RustHomeScreen(),
    );
  }
}
