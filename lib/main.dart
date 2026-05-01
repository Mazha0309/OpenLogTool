import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
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
    DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MultiProvider(
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
          update: (_, syncProvider, logProvider) {
            final provider = logProvider ?? LogProvider();
            provider.setOnDataChanged(() async {
              if (syncProvider.settings.syncEnabled &&
                  syncProvider.settings.syncMode == 'realtime') {
                await syncProvider.triggerSyncAndWait();
              }
            });
            return provider;
          },
        ),
        ],
        child: MyApp(
          lightDynamic: lightDynamic,
          darkDynamic: darkDynamic,
        ),
      );
    },
  ),
  );
}

class MyApp extends StatelessWidget {
  final ColorScheme? lightDynamic;
  final ColorScheme? darkDynamic;

  const MyApp({super.key, this.lightDynamic, this.darkDynamic});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDark = settingsProvider.isDarkMode;
    final themeColor = settingsProvider.themeColor;
    final fontFamily = settingsProvider.fontFamily;


    final baseLight = (lightDynamic != null && settingsProvider.monetColorEnabled)
        ? lightDynamic!
        : ColorScheme.fromSeed(seedColor: themeColor, brightness: Brightness.light);
    final baseDark = (darkDynamic != null && settingsProvider.monetColorEnabled)
        ? darkDynamic!
        : ColorScheme.fromSeed(seedColor: themeColor, brightness: Brightness.dark);

    final vividRed = const Color(0xFFDC2626);

    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseLight.harmonized().copyWith(error: vividRed),
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
        colorScheme: baseDark.harmonized().copyWith(error: vividRed),
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
