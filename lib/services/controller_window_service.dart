import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/screens/controller_display_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

enum ControllerWindowMode { floating, secondDisplay }

bool get supportsControllerDesktopWindows =>
    !kIsWeb &&
    const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

class ControllerWindowLaunch {
  const ControllerWindowLaunch({
    required this.mode,
    required this.data,
    required this.preferences,
  });

  factory ControllerWindowLaunch.fromArguments(String arguments) {
    final map = Map<String, Object?>.from(jsonDecode(arguments) as Map);
    if (map['businessId'] != businessId) {
      throw const FormatException('Not a controller display window');
    }
    return ControllerWindowLaunch(
      mode: ControllerWindowMode.values.firstWhere(
        (mode) => mode.name == map['mode'],
        orElse: () => ControllerWindowMode.floating,
      ),
      data: ControllerDisplayDto.fromJson(map['data']),
      preferences: ControllerDisplayPreferences.fromJson(map['preferences']),
    );
  }

  static const businessId = 'controllerDisplay';

  final ControllerWindowMode mode;
  final ControllerDisplayDto data;
  final ControllerDisplayPreferences preferences;

  String toArguments() => jsonEncode({
        'businessId': businessId,
        'mode': mode.name,
        'data': data.toJson(),
        'preferences': preferences.toJson(),
      });
}

/// 桌面多窗口入口与更新通道。移动端只使用普通全屏路由。
class ControllerWindowService {
  ControllerWindowService._();

  static Future<ControllerWindowLaunch?> currentWindowLaunch() async {
    if (!supportsControllerDesktopWindows) return null;
    await windowManager.ensureInitialized();
    final current = await WindowController.fromCurrentEngine();
    if (current.arguments.isEmpty) return null;
    try {
      return ControllerWindowLaunch.fromArguments(current.arguments);
    } on FormatException {
      return null;
    }
  }

  static Future<void> open({
    required ControllerWindowMode mode,
    required ControllerDisplayDto data,
    required ControllerDisplayPreferences preferences,
  }) async {
    if (!supportsControllerDesktopWindows) {
      throw UnsupportedError('CONTROLLER_WINDOWS_UNSUPPORTED');
    }
    final launch = ControllerWindowLaunch(
      mode: mode,
      data: data,
      preferences: preferences,
    );
    for (final window in await WindowController.getAll()) {
      if (_matches(window, mode)) {
        await window.invokeMethod<void>('controllerDisplay.update', {
          'data': data.toJson(),
          'preferences': preferences.toJson(),
        });
        await window.show();
        return;
      }
    }
    await WindowController.create(
      WindowConfiguration(
        arguments: launch.toArguments(),
        hiddenAtLaunch: true,
      ),
    );
  }

  static Future<void> updateOpenWindows({
    required ControllerDisplayDto data,
    required ControllerDisplayPreferences preferences,
  }) async {
    if (!supportsControllerDesktopWindows) return;
    for (final window in await WindowController.getAll()) {
      if (_isControllerWindow(window)) {
        await window.invokeMethod<void>('controllerDisplay.update', {
          'data': data.toJson(),
          'preferences': preferences.toJson(),
        });
      }
    }
  }

  static Future<void> closeAll() async {
    if (!supportsControllerDesktopWindows) return;
    for (final window in await WindowController.getAll()) {
      if (_isControllerWindow(window)) {
        await window.invokeMethod<void>('controllerDisplay.close');
      }
    }
  }

  static bool _matches(
    WindowController window,
    ControllerWindowMode mode,
  ) {
    try {
      return ControllerWindowLaunch.fromArguments(window.arguments).mode ==
          mode;
    } on FormatException {
      return false;
    }
  }

  static bool _isControllerWindow(WindowController window) {
    try {
      ControllerWindowLaunch.fromArguments(window.arguments);
      return true;
    } on FormatException {
      return false;
    }
  }
}

/// 子窗口专用 App：不加载数据库、Rust 或主应用 Provider。
class ControllerDisplayWindowApp extends StatefulWidget {
  const ControllerDisplayWindowApp({super.key, required this.launch});

  final ControllerWindowLaunch launch;

  @override
  State<ControllerDisplayWindowApp> createState() =>
      _ControllerDisplayWindowAppState();
}

class _ControllerDisplayWindowAppState
    extends State<ControllerDisplayWindowApp> {
  late ControllerDisplayDto _data = widget.launch.data;
  late ControllerDisplayPreferences _preferences = widget.launch.preferences;

  @override
  void initState() {
    super.initState();
    _configureWindow();
  }

  Future<void> _configureWindow() async {
    await windowManager.ensureInitialized();
    final locale = resolveAppLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
      AppLocalizations.supportedLocales,
    );
    final l10n = await AppLocalizations.delegate.load(locale);
    final current = await WindowController.fromCurrentEngine();
    await current.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'controllerDisplay.update':
          final arguments = Map<String, Object?>.from(call.arguments as Map);
          if (mounted) {
            setState(() {
              _data = ControllerDisplayDto.fromJson(arguments['data']);
              // 子窗口拥有当前设备的显示偏好，实时数据更新不能覆盖它。
            });
          }
          return null;
        case 'controllerDisplay.close':
          await windowManager.close();
          return null;
        default:
          throw MissingPluginException('Unknown method ${call.method}');
      }
    });

    final floating = widget.launch.mode == ControllerWindowMode.floating;
    final options = WindowOptions(
      size: floating ? const Size(560, 780) : const Size(1280, 800),
      minimumSize: floating ? const Size(420, 560) : const Size(800, 600),
      center: true,
      title: floating
          ? l10n.controllerFloatingWindowTitle
          : l10n.controllerScreenTitle,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAlwaysOnTop(floating);
      if (!floating) await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> _updatePreferences(
    ControllerDisplayPreferences preferences,
  ) async {
    setState(() => _preferences = preferences);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      controllerDisplayPreferencesStorageKey,
      jsonEncode(preferences.toJson()),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.controllerScreenTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeResolutionCallback: resolveAppLocale,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF64B5F6),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: ControllerDisplayScreen(
          data: _data,
          preferences: _preferences,
          onPreferencesChanged: _updatePreferences,
          onClose: windowManager.close,
        ),
      );
}
