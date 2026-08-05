import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/app_logger.dart';

void main() {
  tearDown(() {
    AppLogger.instance.resetForTest();
  });

  test('writes entries to ring buffer', () {
    AppLogger.instance.debug('d1');
    AppLogger.instance.info('i1');
    AppLogger.instance.error('e1', StackTrace.current);
    final lines = AppLogger.instance.snapshot();
    expect(lines.any((l) => l.contains('d1')), isTrue);
    expect(lines.any((l) => l.contains('i1')), isTrue);
    expect(lines.any((l) => l.contains('e1')), isTrue);
  });

  test('rotates ring buffer at capacity', () {
    for (var i = 0; i < 600; i++) {
      AppLogger.instance.info('msg$i');
    }
    final lines = AppLogger.instance.snapshot();
    expect(lines.length, 500);
    expect(lines.any((l) => l.contains('msg0')), isFalse);
    expect(lines.any((l) => l.contains('msg599')), isTrue);
  });

  test('writes to file with rotation', () async {
    final dir = await Directory.systemTemp.createTemp('olt-log-test');
    addTearDown(() => dir.delete(recursive: true));
    await AppLogger.instance.initForTest(logDir: dir);
    AppLogger.instance.error('boom', StackTrace.current);
    await AppLogger.instance.flushForTest();
    final file = File('${dir.path}/app.log');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync().contains('boom'), isTrue);
  });
}
