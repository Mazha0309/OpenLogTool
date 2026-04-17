import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/sync_provider.dart';
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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => LogProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
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
    final isDark = settingsProvider.isDarkMode;
    final themeColor = settingsProvider.themeColor;
    final fontFamily = settingsProvider.fontFamily;

    final foruiTheme = FThemeData.inherit(
      colorScheme: FColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        background: isDark ? const Color(0xFF09090B) : const Color(0xFFFFFFFF),
        foreground: isDark ? const Color(0xFFFAFAFA) : const Color(0xFF09090B),
        primary: themeColor,
        primaryForeground:
            isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF),
        secondary: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
        secondaryForeground:
            isDark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B),
        muted: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
        mutedForeground:
            isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
        destructive: const Color(0xFFEF4444),
        destructiveForeground: const Color(0xFFFAFAFA),
        error: const Color(0xFFEF4444),
        errorForeground: const Color(0xFFFAFAFA),
        border: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
      ),
    );

    return MaterialApp(
      title: 'OpenLogTool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeColor,
          brightness: Brightness.light,
        ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeColor,
          brightness: Brightness.dark,
        ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      themeMode: settingsProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FTheme(
        data: foruiTheme,
        child: const HomeScreen(),
      ),
    );
  }
}
