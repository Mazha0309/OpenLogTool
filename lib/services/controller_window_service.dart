import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/screens/controller_display_screen.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';

enum ControllerWindowMode { floating, secondDisplay }

typedef ControllerWindowPreferencesChanged = FutureOr<void> Function(
  ControllerDisplayPreferences preferences,
);

bool get supportsControllerDesktopWindows =>
    !kIsWeb &&
    const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

/// Visual settings copied from the main application into a controller child
/// process. Child processes intentionally do not read SharedPreferences, so a
/// full appearance snapshot is part of every launch/update message.
class ControllerWindowAppearance {
  const ControllerWindowAppearance({
    this.themeColor = const Color(0xFF2196F3),
    this.isDarkMode = false,
    this.fontFamily,
    this.locale,
  });

  factory ControllerWindowAppearance.fromJson(Object? value) {
    if (value == null) return const ControllerWindowAppearance();
    final map = _objectMap(value, 'controllerWindowAppearance');
    final colorValue = map['themeColor'];
    if (colorValue != null && colorValue is! int) {
      throw const FormatException('Controller theme color must be an integer');
    }
    final rawFont = map['fontFamily'];
    if (rawFont != null && rawFont is! String) {
      throw const FormatException('Controller font family must be a string');
    }
    final rawLocale = map['locale'];
    if (rawLocale != null && rawLocale is! String) {
      throw const FormatException('Controller locale must be a string');
    }
    final parsedColor =
        colorValue is int ? Color(colorValue) : const Color(0xFF2196F3);
    final parsedFont =
        rawFont is String && rawFont.trim().isNotEmpty ? rawFont : null;
    return ControllerWindowAppearance(
      themeColor: parsedColor,
      isDarkMode: map['isDarkMode'] == true,
      fontFamily: parsedFont,
      locale: _controllerLocaleFromStorage(rawLocale as String?),
    );
  }

  final Color themeColor;
  final bool isDarkMode;
  final String? fontFamily;
  final Locale? locale;

  Locale resolveLocale(Locale systemLocale) => resolveAppLocale(
        locale ?? systemLocale,
        AppLocalizations.supportedLocales,
      );

  Map<String, Object?> toJson() => {
        'themeColor': themeColor.toARGB32(),
        'isDarkMode': isDarkMode,
        'fontFamily': fontFamily,
        'locale': _controllerLocaleToStorage(locale),
      };
}

Locale? _controllerLocaleFromStorage(String? locale) => switch (locale) {
      null => null,
      'zh_CN' => const Locale('zh', 'CN'),
      'en_US' => const Locale('en', 'US'),
      _ => throw FormatException('Unsupported controller locale: $locale'),
    };

String? _controllerLocaleToStorage(Locale? locale) => switch (locale) {
      null => null,
      Locale(languageCode: 'zh', countryCode: 'CN') => 'zh_CN',
      Locale(languageCode: 'en', countryCode: 'US') => 'en_US',
      _ => throw ArgumentError.value(locale, 'locale', 'is not supported'),
    };

class ControllerWindowLaunch {
  const ControllerWindowLaunch({
    required this.mode,
    required this.data,
    required this.preferences,
    this.appearance = const ControllerWindowAppearance(),
  });

  factory ControllerWindowLaunch.fromArguments(String arguments) {
    try {
      return ControllerWindowLaunch.fromJson(jsonDecode(arguments));
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid controller window arguments', error);
    }
  }

  factory ControllerWindowLaunch.fromJson(Object? value) {
    final map = _objectMap(value, 'controllerWindowLaunch');
    if (map['businessId'] != businessId) {
      throw const FormatException('Not a controller display window');
    }
    final modeName = map['mode'];
    if (modeName is! String) {
      throw const FormatException('Controller window mode is missing');
    }
    final mode = ControllerWindowMode.values.where(
      (candidate) => candidate.name == modeName,
    );
    if (mode.length != 1) {
      throw FormatException('Unknown controller window mode: $modeName');
    }
    return ControllerWindowLaunch(
      mode: mode.single,
      data: ControllerDisplayDto.fromJson(map['data']),
      preferences: ControllerDisplayPreferences.fromJson(map['preferences']),
      appearance: ControllerWindowAppearance.fromJson(map['appearance']),
    );
  }

  static const businessId = 'controllerDisplay';

  final ControllerWindowMode mode;
  final ControllerDisplayDto data;
  final ControllerDisplayPreferences preferences;
  final ControllerWindowAppearance appearance;

  Map<String, Object?> toJson() => {
        'businessId': businessId,
        'mode': mode.name,
        'data': data.toJson(),
        'preferences': preferences.toJson(),
        'appearance': appearance.toJson(),
      };

  String toArguments() => jsonEncode(toJson());
}

enum ControllerWindowMessageType { initialize, update, show, close }

class ControllerWindowMessage {
  const ControllerWindowMessage({
    required this.type,
    required this.revision,
    this.launch,
  });

  final ControllerWindowMessageType type;
  final int revision;
  final ControllerWindowLaunch? launch;
}

/// Bounded JSON-lines protocol used only over an OS parent/child pipe.
class ControllerWindowProtocol {
  const ControllerWindowProtocol._();

  static const int version = 1;
  static const int maxMessageBytes = 256 * 1024;
  static const String childFlag = '--openlogtool-controller-child';
  static const String readyMarker = '__OPENLOGTOOL_CONTROLLER_READY_V1__';

  static String encode({
    required ControllerWindowMessageType type,
    required int revision,
    ControllerWindowLaunch? launch,
  }) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must not be negative');
    }
    if (type != ControllerWindowMessageType.close && launch == null) {
      throw ArgumentError('A full controller snapshot is required for $type');
    }
    final encoded = jsonEncode({
      'protocolVersion': version,
      'type': type.name,
      'revision': revision,
      if (launch != null) 'launch': launch.toJson(),
    });
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const FormatException('Controller window message is too large');
    }
    return encoded;
  }

  static ControllerWindowMessage decode(String encoded) {
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const FormatException('Controller window message is too large');
    }
    final map = _objectMap(jsonDecode(encoded), 'controllerWindowMessage');
    if (map['protocolVersion'] != version) {
      throw const FormatException('Unsupported controller window protocol');
    }
    final rawType = map['type'];
    if (rawType is! String) {
      throw const FormatException('Controller window message type is missing');
    }
    final matchingTypes = ControllerWindowMessageType.values.where(
      (candidate) => candidate.name == rawType,
    );
    if (matchingTypes.length != 1) {
      throw FormatException('Unknown controller window message type: $rawType');
    }
    final revision = map['revision'];
    if (revision is! int || revision < 0) {
      throw const FormatException('Invalid controller window revision');
    }
    final type = matchingTypes.single;
    final rawLaunch = map['launch'];
    if (type != ControllerWindowMessageType.close && rawLaunch == null) {
      throw const FormatException('Controller window snapshot is missing');
    }
    return ControllerWindowMessage(
      type: type,
      revision: revision,
      launch:
          rawLaunch == null ? null : ControllerWindowLaunch.fromJson(rawLaunch),
    );
  }
}

enum ControllerWindowChildEventType { preferencesChanged }

class ControllerWindowChildEvent {
  const ControllerWindowChildEvent({
    required this.type,
    required this.preferences,
  });

  final ControllerWindowChildEventType type;
  final ControllerDisplayPreferences preferences;
}

/// Child-to-parent messages share stdout with the process-ready marker and
/// diagnostics, so protocol lines use an explicit prefix and bounded payload.
class ControllerWindowChildEventProtocol {
  const ControllerWindowChildEventProtocol._();

  static const String prefix = '__OPENLOGTOOL_CONTROLLER_EVENT_V1__';

  static String encodePreferencesChanged(
    ControllerDisplayPreferences preferences,
  ) {
    final encoded = '$prefix${jsonEncode({
          'protocolVersion': ControllerWindowProtocol.version,
          'type': ControllerWindowChildEventType.preferencesChanged.name,
          'preferences': preferences.toJson(),
        })}';
    if (utf8.encode(encoded).length >
        ControllerWindowProtocol.maxMessageBytes) {
      throw const FormatException('Controller window event is too large');
    }
    return encoded;
  }

  static ControllerWindowChildEvent? tryDecode(String encoded) {
    if (!encoded.startsWith(prefix)) return null;
    if (utf8.encode(encoded).length >
        ControllerWindowProtocol.maxMessageBytes) {
      throw const FormatException('Controller window event is too large');
    }
    final map = _objectMap(
      jsonDecode(encoded.substring(prefix.length)),
      'controllerWindowChildEvent',
    );
    if (map['protocolVersion'] != ControllerWindowProtocol.version) {
      throw const FormatException('Unsupported controller window event');
    }
    if (map['type'] != ControllerWindowChildEventType.preferencesChanged.name) {
      throw FormatException(
        'Unknown controller window event type: ${map['type']}',
      );
    }
    return ControllerWindowChildEvent(
      type: ControllerWindowChildEventType.preferencesChanged,
      preferences: ControllerDisplayPreferences.fromJson(map['preferences']),
    );
  }
}

/// Splits pipe input without allowing an unbounded unterminated JSON line.
class ControllerWindowPipeDecoder {
  final List<int> _pending = <int>[];

  List<String> add(List<int> chunk) {
    final messages = <String>[];
    for (final byte in chunk) {
      if (byte == 0x0a) {
        if (_pending.isNotEmpty && _pending.last == 0x0d) {
          _pending.removeLast();
        }
        if (_pending.isNotEmpty) {
          messages.add(utf8.decode(_pending, allowMalformed: false));
        }
        _pending.clear();
        continue;
      }
      _pending.add(byte);
      if (_pending.length > ControllerWindowProtocol.maxMessageBytes) {
        _pending.clear();
        throw const FormatException('Controller window message is too large');
      }
    }
    return messages;
  }

  void finish() {
    if (_pending.isNotEmpty) {
      _pending.clear();
      throw const FormatException('Truncated controller window message');
    }
  }
}

class ControllerWindowChildSession {
  ControllerWindowChildSession._({
    required this.launch,
    required this.initialRevision,
    required StreamController<ControllerWindowMessage> commands,
    required StreamSubscription<List<int>> inputSubscription,
  })  : commands = commands.stream,
        _commands = commands,
        _inputSubscription = inputSubscription;

  final ControllerWindowLaunch launch;
  final int initialRevision;
  final Stream<ControllerWindowMessage> commands;
  final StreamController<ControllerWindowMessage> _commands;
  final StreamSubscription<List<int>> _inputSubscription;

  static Future<ControllerWindowChildSession> fromInput(
    Stream<List<int>> input, {
    Duration initializationTimeout = const Duration(seconds: 8),
  }) async {
    final decoder = ControllerWindowPipeDecoder();
    final commands = StreamController<ControllerWindowMessage>();
    final initialized = Completer<ControllerWindowMessage>();
    var lastRevision = -1;
    var stopped = false;
    Future<void>? stopping;
    late final StreamSubscription<List<int>> subscription;

    Future<void> stopWithError(Object error, StackTrace stackTrace) {
      final existingStop = stopping;
      if (existingStop != null) return existingStop;
      stopped = true;
      if (!initialized.isCompleted) {
        initialized.completeError(error, stackTrace);
      } else if (!commands.isClosed) {
        commands.add(
          ControllerWindowMessage(
            type: ControllerWindowMessageType.close,
            revision: lastRevision + 1,
          ),
        );
      }
      if (!commands.isClosed) commands.close();
      return stopping = subscription.cancel();
    }

    subscription = input.listen(
      (chunk) {
        if (stopped) return;
        try {
          for (final line in decoder.add(chunk)) {
            final message = ControllerWindowProtocol.decode(line);
            if (message.revision <= lastRevision) continue;
            lastRevision = message.revision;
            if (!initialized.isCompleted) {
              if (message.type != ControllerWindowMessageType.initialize ||
                  message.launch == null) {
                throw const FormatException(
                  'The first controller window message must initialize it',
                );
              }
              initialized.complete(message);
            } else if (message.type == ControllerWindowMessageType.initialize) {
              throw const FormatException(
                'Controller window was initialized more than once',
              );
            } else {
              commands.add(message);
            }
          }
        } catch (error, stackTrace) {
          unawaited(stopWithError(error, stackTrace));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(stopWithError(error, stackTrace));
      },
      onDone: () {
        if (stopped) return;
        try {
          decoder.finish();
          unawaited(
            stopWithError(
              const FormatException('Controller window parent disconnected'),
              StackTrace.current,
            ),
          );
        } catch (error, stackTrace) {
          unawaited(stopWithError(error, stackTrace));
        }
      },
      cancelOnError: false,
    );

    try {
      final message = await initialized.future.timeout(initializationTimeout);
      return ControllerWindowChildSession._(
        launch: message.launch!,
        initialRevision: message.revision,
        commands: commands,
        inputSubscription: subscription,
      );
    } catch (_) {
      final existingStop = stopping;
      if (existingStop != null) {
        await existingStop;
      } else {
        stopped = true;
        await subscription.cancel();
        if (!commands.isClosed) commands.close();
      }
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _inputSubscription.cancel();
    if (!_commands.isClosed) _commands.close();
  }
}

/// Keeps the latest complete snapshot for controller windows that are opening
/// or already running. Kept separate so updates during process startup can be
/// covered without launching a real desktop process in unit tests.
class ControllerWindowSnapshotCache {
  final Map<ControllerWindowMode, ControllerWindowLaunch> _latest = {};

  ControllerWindowLaunch? operator [](ControllerWindowMode mode) =>
      _latest[mode];

  void remember(ControllerWindowLaunch launch) {
    _latest[launch.mode] = launch;
  }

  void updateActive({
    required Iterable<ControllerWindowMode> modes,
    required ControllerDisplayDto data,
    required ControllerDisplayPreferences preferences,
    required ControllerWindowAppearance appearance,
  }) {
    for (final mode in modes) {
      _latest[mode] = ControllerWindowLaunch(
        mode: mode,
        data: data,
        preferences: preferences,
        appearance: appearance,
      );
    }
  }

  void updatePreferences({
    required Iterable<ControllerWindowMode> modes,
    required ControllerDisplayPreferences preferences,
  }) {
    for (final mode in modes) {
      final current = _latest[mode];
      if (current == null) continue;
      _latest[mode] = ControllerWindowLaunch(
        mode: mode,
        data: current.data,
        preferences: preferences,
        appearance: current.appearance,
      );
    }
  }

  void clear() => _latest.clear();
}

/// Desktop controller windows run as separate processes. A compositor/plugin
/// crash in a presentation window therefore cannot take down the clerk UI.
class ControllerWindowService {
  ControllerWindowService._();

  static final Map<ControllerWindowMode, _ControllerChildProcess> _children =
      <ControllerWindowMode, _ControllerChildProcess>{};
  static final Map<ControllerWindowMode, Future<_ControllerChildProcess>>
      _opening = <ControllerWindowMode, Future<_ControllerChildProcess>>{};
  static final ControllerWindowSnapshotCache _snapshots =
      ControllerWindowSnapshotCache();
  static final Map<ControllerWindowMode, ControllerWindowPreferencesChanged>
      _preferencesChangedCallbacks = {};
  static int _generation = 0;

  static bool isControllerChildArguments(List<String> arguments) =>
      arguments.length == 1 &&
      arguments.single == ControllerWindowProtocol.childFlag;

  static Future<ControllerWindowChildSession?> currentWindowLaunch(
    List<String> arguments,
  ) async {
    if (!isControllerChildArguments(arguments)) return null;
    if (!supportsControllerDesktopWindows) {
      throw UnsupportedError('CONTROLLER_WINDOWS_UNSUPPORTED');
    }
    return ControllerWindowChildSession.fromInput(stdin);
  }

  static Future<void> open({
    required ControllerWindowMode mode,
    required ControllerDisplayDto data,
    required ControllerDisplayPreferences preferences,
    required ControllerWindowAppearance appearance,
    required ControllerWindowPreferencesChanged onPreferencesChanged,
  }) async {
    if (!supportsControllerDesktopWindows) {
      throw UnsupportedError('CONTROLLER_WINDOWS_UNSUPPORTED');
    }
    final launch = ControllerWindowLaunch(
      mode: mode,
      data: data,
      preferences: preferences,
      appearance: appearance,
    );
    _preferencesChangedCallbacks[mode] = onPreferencesChanged;
    _snapshots.remember(launch);

    final existing = _children[mode];
    if (existing != null && !existing.exited) {
      await existing.send(ControllerWindowMessageType.show, launch: launch);
      return;
    }

    final pending = _opening[mode];
    if (pending != null) {
      final child = await pending;
      final latest = _snapshots[mode] ?? launch;
      if (!child.exited) {
        await child.send(ControllerWindowMessageType.show, launch: latest);
      }
      return;
    }

    final generation = _generation;
    final opening = _spawn(mode, generation);
    _opening[mode] = opening;
    try {
      await opening;
    } finally {
      if (identical(_opening[mode], opening)) _opening.remove(mode);
    }
  }

  static Future<_ControllerChildProcess> _spawn(
    ControllerWindowMode mode,
    int generation,
  ) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      const [ControllerWindowProtocol.childFlag],
      mode: ProcessStartMode.normal,
    );
    if (generation != _generation) {
      process.kill();
      throw StateError('Controller window launch was cancelled');
    }

    late final _ControllerChildProcess child;
    child = _ControllerChildProcess(
      process: process,
      onPreferencesChanged: (preferences) =>
          _handlePreferencesChanged(mode, preferences),
      onExit: () {
        if (identical(_children[mode], child)) _children.remove(mode);
      },
    );
    _children[mode] = child;

    final launch = _snapshots[mode];
    if (launch == null) {
      await child.shutdown();
      throw StateError('Controller window state is unavailable');
    }
    final ready = child.ready.future.timeout(const Duration(seconds: 8));
    try {
      await Future.wait<void>(
        [
          child.send(
            ControllerWindowMessageType.initialize,
            launch: launch,
          ),
          ready,
        ],
        eagerError: true,
      );

      final latest = _snapshots[mode];
      if (latest != null && !child.exited) {
        await child.send(ControllerWindowMessageType.update, launch: latest);
      }
      return child;
    } catch (error, stackTrace) {
      await child.shutdown();
      if (identical(_children[mode], child)) _children.remove(mode);
      Error.throwWithStackTrace(
        StateError('Controller window failed to start: $error'),
        stackTrace,
      );
    }
  }

  static Future<void> updateOpenWindows({
    required ControllerDisplayDto data,
    required ControllerDisplayPreferences preferences,
    required ControllerWindowAppearance appearance,
  }) async {
    if (!supportsControllerDesktopWindows) return;
    final activeModes = <ControllerWindowMode>{
      ..._opening.keys,
      ..._children.keys,
    };
    _snapshots.updateActive(
      modes: activeModes,
      data: data,
      preferences: preferences,
      appearance: appearance,
    );
    for (final entry in _children.entries.toList(growable: false)) {
      final child = entry.value;
      if (child.exited) continue;
      final launch = _snapshots[entry.key]!;
      try {
        await child.send(ControllerWindowMessageType.update, launch: launch);
      } catch (_) {
        if (identical(_children[entry.key], child)) {
          _children.remove(entry.key);
        }
      }
    }
  }

  static Future<void> _handlePreferencesChanged(
    ControllerWindowMode sourceMode,
    ControllerDisplayPreferences preferences,
  ) async {
    final activeModes = <ControllerWindowMode>{
      ..._opening.keys,
      ..._children.keys,
    };
    _snapshots.updatePreferences(
      modes: activeModes,
      preferences: preferences,
    );

    final callback = _preferencesChangedCallbacks[sourceMode];
    final persistence = callback == null
        ? null
        : Future<void>.sync(() => callback(preferences));
    for (final entry in _children.entries.toList(growable: false)) {
      final child = entry.value;
      final launch = _snapshots[entry.key];
      if (child.exited || launch == null) continue;
      try {
        await child.send(ControllerWindowMessageType.update, launch: launch);
      } catch (_) {
        if (identical(_children[entry.key], child)) {
          _children.remove(entry.key);
        }
      }
    }
    if (persistence != null) await persistence;
  }

  static Future<void> closeAll() async {
    _generation += 1;
    _opening.clear();
    final children = _children.values.toSet().toList(growable: false);
    _children.clear();
    _snapshots.clear();
    _preferencesChangedCallbacks.clear();
    await Future.wait(children.map((child) => child.shutdown()));
  }
}

class _ControllerChildProcess {
  _ControllerChildProcess({
    required this.process,
    required ControllerWindowPreferencesChanged onPreferencesChanged,
    required void Function() onExit,
  })  : _onPreferencesChanged = onPreferencesChanged,
        _onExit = onExit {
    // The owning startup path still awaits this future. This extra listener
    // prevents a very early child exit from becoming an unhandled zone error
    // before that await is installed (for example, when the first pipe write
    // fails at the same time).
    ready.future.ignore();
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line == ControllerWindowProtocol.readyMarker && !ready.isCompleted) {
        ready.complete();
        return;
      }
      try {
        final event = ControllerWindowChildEventProtocol.tryDecode(line);
        if (event != null) {
          unawaited(
            Future<void>.sync(
              () => _onPreferencesChanged(event.preferences),
            ).catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                '[ControllerWindow] preference update failed: $error',
              );
            }),
          );
        }
      } catch (error) {
        debugPrint('[ControllerWindow] invalid child event: $error');
      }
    });
    _stderrSubscription = process.stderr.listen((_) {});
    process.exitCode.then((code) {
      exited = true;
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('Controller window exited before ready (code $code)'),
        );
      }
      _onExit();
      unawaited(_stdoutSubscription.cancel());
      unawaited(_stderrSubscription.cancel());
    });
  }

  final Process process;
  final ControllerWindowPreferencesChanged _onPreferencesChanged;
  final void Function() _onExit;
  final Completer<void> ready = Completer<void>();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool exited = false;

  Future<void> send(
    ControllerWindowMessageType type, {
    ControllerWindowLaunch? launch,
  }) {
    if (exited) {
      return Future<void>.error(StateError('Controller window has exited'));
    }
    final encoded = ControllerWindowProtocol.encode(
      type: type,
      revision: ++_revision,
      launch: launch,
    );
    _writes = _writes.then((_) async {
      if (exited) throw StateError('Controller window has exited');
      process.stdin.writeln(encoded);
      await process.stdin.flush();
    });
    return _writes;
  }

  Future<void> shutdown() async {
    if (exited) return;
    try {
      await send(ControllerWindowMessageType.close);
    } catch (_) {
      // The process may already have closed its pipe after a manual close.
    }
    try {
      await process.stdin.close();
    } catch (_) {
      // Closing stdin is still attempted when the serialized write queue failed.
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        // The OS owns final cleanup if a process cannot be reaped promptly.
      }
    }
  }
}

/// Child-process App: it intentionally does not initialize Rust, the database,
/// or main application providers.
class ControllerDisplayWindowApp extends StatefulWidget {
  const ControllerDisplayWindowApp({
    super.key,
    required this.session,
  });

  final ControllerWindowChildSession session;

  @override
  State<ControllerDisplayWindowApp> createState() =>
      _ControllerDisplayWindowAppState();
}

class _ControllerDisplayWindowAppState extends State<ControllerDisplayWindowApp>
    with WindowListener, WidgetsBindingObserver {
  late ControllerDisplayDto _data = widget.session.launch.data;
  late ControllerDisplayPreferences _preferences =
      widget.session.launch.preferences;
  late ControllerWindowAppearance _appearance =
      widget.session.launch.appearance;
  late int _lastRevision = widget.session.initialRevision;
  late final StreamSubscription<ControllerWindowMessage> _commands;
  var _windowReady = false;
  var _closeRequested = false;
  var _terminating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _commands = widget.session.commands.listen(_handleCommand);
    _configureWindow().catchError((Object error, StackTrace stackTrace) {
      debugPrint('[ControllerWindow] child initialization failed: $error');
      _closeRequested = true;
      _terminateChildWindow().catchError((Object closeError) {
        debugPrint('[ControllerWindow] child cleanup failed: $closeError');
      });
    });
  }

  void _handleCommand(ControllerWindowMessage message) {
    if (message.revision <= _lastRevision) return;
    _lastRevision = message.revision;
    switch (message.type) {
      case ControllerWindowMessageType.initialize:
        return;
      case ControllerWindowMessageType.update:
      case ControllerWindowMessageType.show:
        final launch = message.launch;
        if (launch != null && mounted) {
          final localeChanged = launch.appearance.locale != _appearance.locale;
          setState(() {
            _data = launch.data;
            _preferences = launch.preferences;
            _appearance = launch.appearance;
          });
          if (localeChanged && _windowReady) {
            unawaited(_updateWindowTitle(launch.appearance));
          }
        }
        if (message.type == ControllerWindowMessageType.show && _windowReady) {
          unawaited(windowManager.show());
          unawaited(windowManager.focus());
        }
        return;
      case ControllerWindowMessageType.close:
        _closeRequested = true;
        if (_windowReady) unawaited(_terminateChildWindow());
    }
  }

  Future<void> _configureWindow() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    final locale = _appearance.resolveLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    final l10n = await AppLocalizations.delegate.load(locale);
    final floating =
        widget.session.launch.mode == ControllerWindowMode.floating;
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
    _windowReady = true;
    await _updateWindowTitle(_appearance);
    if (_closeRequested) {
      await _terminateChildWindow();
      return;
    }
    stdout.writeln(ControllerWindowProtocol.readyMarker);
    await stdout.flush();
  }

  Future<void> _updateWindowTitle(
    ControllerWindowAppearance appearance,
  ) async {
    final locale = appearance.resolveLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    final l10n = await AppLocalizations.delegate.load(locale);
    if (!mounted || !_windowReady || _appearance.locale != appearance.locale) {
      return;
    }
    final floating =
        widget.session.launch.mode == ControllerWindowMode.floating;
    await windowManager.setTitle(
      floating
          ? l10n.controllerFloatingWindowTitle
          : l10n.controllerScreenTitle,
    );
  }

  void _updatePreferences(ControllerDisplayPreferences preferences) {
    setState(() => _preferences = preferences);
    unawaited(_publishPreferences(preferences));
  }

  Future<void> _publishPreferences(
    ControllerDisplayPreferences preferences,
  ) async {
    try {
      stdout.writeln(
        ControllerWindowChildEventProtocol.encodePreferencesChanged(
          preferences,
        ),
      );
      await stdout.flush();
    } catch (error) {
      debugPrint('[ControllerWindow] preference publish failed: $error');
    }
  }

  Future<void> _terminateChildWindow() async {
    if (_terminating) return;
    _terminating = true;
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    unawaited(_terminateChildWindow());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_appearance.locale == null && _windowReady) {
      unawaited(_updateWindowTitle(_appearance));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    unawaited(_commands.cancel());
    unawaited(widget.session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.controllerScreenTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _appearance.locale,
        localeResolutionCallback: resolveAppLocale,
        theme: buildAppTheme(
          brightness: Brightness.light,
          seedColor: _appearance.themeColor,
          fontFamily: _appearance.fontFamily,
        ),
        darkTheme: buildAppTheme(
          brightness: Brightness.dark,
          seedColor: _appearance.themeColor,
          fontFamily: _appearance.fontFamily,
        ),
        themeMode: _appearance.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: ControllerDisplayScreen(
          data: _data,
          preferences: _preferences,
          onPreferencesChanged: _updatePreferences,
          onClose: _terminateChildWindow,
        ),
      );
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value is! Map) throw FormatException('$name must be an object');
  try {
    return Map<String, Object?>.from(value);
  } catch (error) {
    throw FormatException('$name must use string keys', error);
  }
}
