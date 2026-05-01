import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/providers/sync_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/screens/home_screen.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
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
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final themeColor = settingsProvider.themeColor;
    final fontFamily = settingsProvider.fontFamily;

    const vividRed = Color(0xFFDC2626);

    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeColor,
          brightness: Brightness.light,
        ).copyWith(error: vividRed),
        fontFamily: fontFamily,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeColor,
          brightness: Brightness.dark,
        ).copyWith(error: vividRed),
        fontFamily: fontFamily,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade800),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      themeMode: settingsProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
