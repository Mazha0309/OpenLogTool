import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/services/controller_window_service.dart';

void main() {
  test('desktop child window arguments preserve display state', () {
    const launch = _launch;

    final restored = ControllerWindowLaunch.fromArguments(
      launch.toArguments(),
    );

    expect(restored.mode, ControllerWindowMode.secondDisplay);
    expect(restored.data.sessionTitle, '周日晚间点名');
    expect(restored.data.currentOrdinal, 12);
    expect(restored.data.current.toJson(), _launch.data.current.toJson());
    expect(
      restored.preferences.detail,
      ControllerDisplayDetail.standard,
    );
    expect(restored.appearance.themeColor, const Color(0xFF9C27B0));
    expect(restored.appearance.isDarkMode, isTrue);
    expect(restored.appearance.fontFamily, 'SarasaGothicSC');
  });

  test('pipe protocol handles split frames and rejects unknown modes', () {
    final encoded = ControllerWindowProtocol.encode(
      type: ControllerWindowMessageType.initialize,
      revision: 1,
      launch: _launch,
    );
    final bytes = utf8.encode('$encoded\n');
    final decoder = ControllerWindowPipeDecoder();
    final first = decoder.add(bytes.sublist(0, bytes.length ~/ 2));
    final second = decoder.add(bytes.sublist(bytes.length ~/ 2));

    expect(first, isEmpty);
    expect(second, hasLength(1));
    final message = ControllerWindowProtocol.decode(second.single);
    expect(message.type, ControllerWindowMessageType.initialize);
    expect(message.revision, 1);
    expect(
      message.launch?.data.current.toJson(),
      _launch.data.current.toJson(),
    );

    final invalid = jsonEncode({
      ..._launch.toJson(),
      'mode': 'not-a-mode',
    });
    expect(
      () => ControllerWindowLaunch.fromArguments(invalid),
      throwsFormatException,
    );
  });

  test('child session receives latest snapshots and closes on parent EOF',
      () async {
    final input = StreamController<List<int>>();
    final sessionFuture = ControllerWindowChildSession.fromInput(
      input.stream,
      initializationTimeout: const Duration(seconds: 1),
    );
    input.add(
      utf8.encode(
        '${ControllerWindowProtocol.encode(
          type: ControllerWindowMessageType.initialize,
          revision: 1,
          launch: _launch,
        )}\n',
      ),
    );
    final session = await sessionFuture;
    final receivedFuture = session.commands.take(2).toList();
    input.add(
      utf8.encode(
        '${ControllerWindowProtocol.encode(
          type: ControllerWindowMessageType.update,
          revision: 2,
          launch: _launch,
        )}\n',
      ),
    );
    await input.close();

    final received = await receivedFuture;
    expect(received.map((message) => message.type), [
      ControllerWindowMessageType.update,
      ControllerWindowMessageType.close,
    ]);
    expect(received.first.revision, 2);
    expect(received.last.revision, 3);
    await session.dispose();
  });

  test('pipe decoder bounds an unterminated message', () {
    final decoder = ControllerWindowPipeDecoder();
    expect(
      () => decoder.add(
        List<int>.filled(
          ControllerWindowProtocol.maxMessageBytes + 1,
          0x61,
        ),
      ),
      throwsFormatException,
    );
  });

  test('snapshot cache refreshes a window while its process is opening', () {
    final cache = ControllerWindowSnapshotCache()..remember(_launch);
    const updatedData = ControllerDisplayDto(
      sessionTitle: '更新后的点名',
      currentOrdinal: 13,
      totalRecords: 12,
      current: ControllerRecordDisplay(callsign: 'BA4BBB'),
    );

    cache.updateActive(
      modes: const [ControllerWindowMode.secondDisplay],
      data: updatedData,
      preferences: const ControllerDisplayPreferences(
        detail: ControllerDisplayDetail.full,
      ),
      appearance: const ControllerWindowAppearance(
        themeColor: Color(0xFFFF9800),
      ),
    );

    expect(cache[ControllerWindowMode.secondDisplay]?.data.currentOrdinal, 13);
    expect(
      cache[ControllerWindowMode.secondDisplay]?.data.current.callsign,
      'BA4BBB',
    );
    expect(
      cache[ControllerWindowMode.secondDisplay]?.appearance.themeColor,
      const Color(0xFFFF9800),
    );
  });

  test('child session rejects a non-initialize first message', () async {
    final input = StreamController<List<int>>();
    final session = ControllerWindowChildSession.fromInput(
      input.stream,
      initializationTimeout: const Duration(seconds: 1),
    );
    input.add(
      utf8.encode(
        '${ControllerWindowProtocol.encode(
          type: ControllerWindowMessageType.update,
          revision: 1,
          launch: _launch,
        )}\n',
      ),
    );

    await expectLater(session, throwsFormatException);
    await input.close();
  });
}

const _launch = ControllerWindowLaunch(
  mode: ControllerWindowMode.secondDisplay,
  data: ControllerDisplayDto(
    sessionTitle: '周日晚间点名',
    currentOrdinal: 12,
    totalRecords: 11,
    current: ControllerRecordDisplay(
      controller: 'BG5CRL',
      callsign: 'BA4AAA',
      time: '20:15',
      rstSent: '59',
      rstRcvd: '57',
      qth: '上海',
      device: 'IC-7300',
      power: '100W',
      antenna: 'DP',
      height: '12m',
      remarks: '移动设台',
    ),
  ),
  preferences: ControllerDisplayPreferences(
    detail: ControllerDisplayDetail.standard,
  ),
  appearance: ControllerWindowAppearance(
    themeColor: Color(0xFF9C27B0),
    isDarkMode: true,
    fontFamily: 'SarasaGothicSC',
  ),
);
