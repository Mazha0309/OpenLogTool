import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;

/// 应用统一日志：桌面写文件（大小轮转），Web 输出 console；始终维护内存环形缓冲。
class AppLogger {
  AppLogger._() {
    logging.Logger.root.level = logging.Level.ALL;
    logging.Logger.root.onRecord.listen(_onRecord);
  }

  static final AppLogger instance = AppLogger._();

  static const int ringCapacity = 500;
  static const int fileMaxBytes = 1024 * 1024;
  static const int fileKeepCount = 3;

  final logging.Logger _logger = logging.Logger('OpenLogTool');
  final List<String> _ring = List.filled(ringCapacity, '', growable: false);
  int _ringIndex = 0;
  int _ringCount = 0;
  File? _file;
  Future<void> _writeChain = Future<void>.value();

  /// 最近日志快照（环形缓冲，按时间顺序）。
  List<String> snapshot() => List.generate(
        _ringCount,
        (i) =>
            _ring[(_ringIndex - _ringCount + i + ringCapacity) % ringCapacity],
      );

  void resetForTest() {
    _ringIndex = 0;
    _ringCount = 0;
    _file = null;
    _writeChain = Future<void>.value();
  }

  /// 等待已入队的文件写入完成（测试用）。
  Future<void> flushForTest() => _writeChain;

  Future<void> initForTest({required Directory logDir}) async {
    await _setupFile(logDir);
  }

  Future<void> init({Directory? logDirOverride}) async {
    logging.Logger.root.level = logging.Level.ALL;
    if (!kIsWeb) {
      final home = Platform.environment['HOME'];
      final defaultDir = home == null
          ? Directory.systemTemp
          : Directory('$home/.local/share/openlogtool/logs');
      try {
        await _setupFile(logDirOverride ?? defaultDir);
      } catch (e) {
        debugPrint('AppLogger file setup failed, logging to memory only: $e');
      }
    }
    info(
        'OpenLogTool logging initialized (web=$kIsWeb, file=${_file != null})');
  }

  Future<void> _setupFile(Directory dir) async {
    await dir.create(recursive: true);
    _file = File('${dir.path}/app.log');
  }

  void _onRecord(logging.LogRecord record) {
    final line = '${record.time.toIso8601String()} [${record.level.name}] '
        '${record.message}'
        '${record.error != null ? '\n  ${record.error}' : ''}'
        '${record.stackTrace != null ? '\n$record.stackTrace' : ''}';
    _ring[_ringIndex] = line;
    _ringIndex = (_ringIndex + 1) % ringCapacity;
    if (_ringCount < ringCapacity) _ringCount++;
    if (kIsWeb) {
      debugPrint(line);
    }
    _writeChain = _writeChain.then((_) => _writeFile(line));
  }

  Future<void> _writeFile(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      if (await file.exists() && await file.length() > fileMaxBytes) {
        for (var i = fileKeepCount - 1; i >= 1; i--) {
          final src = File('${file.path}.$i');
          final dst = File('${file.path}.${i + 1}');
          if (await src.exists()) {
            await dst.writeAsString(await src.readAsString());
          }
        }
        if (await file.exists()) {
          await File('${file.path}.1').writeAsString(await file.readAsString());
          await file.writeAsString('');
        }
      }
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // 写失败静默降级（磁盘满/权限问题不中断应用）
    }
  }

  void debug(String message, [Object? error, StackTrace? stack]) =>
      _logger.fine(message, error, stack);
  void info(String message) => _logger.info(message);
  void warn(String message, [Object? error, StackTrace? stack]) =>
      _logger.warning(message, error, stack);
  void error(String message, [Object? error, StackTrace? stack]) =>
      _logger.severe(message, error, stack);
}
