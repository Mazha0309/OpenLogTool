import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/src/bridge/models/session.dart';

void main() {
  test('normalizes Rust newest-first pages to the client chronological order',
      () {
    final newestFirst = <bridge.LogEntry>[
      _bridgeLog(
        id: 'new',
        time: '2026-07-13T11:00:00Z',
        rstSent: '59',
        rstRcvd: '57',
      ),
      _bridgeLog(
        id: 'old',
        time: '2026-07-13T10:00:00Z',
        rstSent: '58',
        rstRcvd: '47',
      ),
    ];

    final normalized = LogProvider.normalizeLoadedLogs(newestFirst);

    expect(normalized.map((log) => log.id), <String>['old', 'new']);
    expect(
      (normalized.last.report, normalized.last.rstRcvd),
      ('59', '57'),
    );
  });

  test('a closed historical session is read-only at the provider boundary',
      () async {
    final provider = LogProvider(
      sessionListLoader: () async => [_session(status: 'closed')],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    await provider.reloadForSession('history-session');

    expect(provider.currentSessionReadOnly, isTrue);
    await expectLater(
      provider.addLog(
        LogEntry(
          id: 'new-log',
          sessionId: 'history-session',
          time: '2026-07-13T12:00:00Z',
          controller: 'BG5CRL',
          callsign: 'BG5FBT',
          report: '59',
          rstRcvd: '59',
          qth: '',
          device: '',
          power: '',
          antenna: '',
          height: '',
          createdAt: '2026-07-13T12:00:00Z',
          updatedAt: '2026-07-13T12:00:00Z',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SESSION_CLOSED'),
        ),
      ),
    );
    provider.dispose();
  });

  test('an active session remains writable after its state is loaded',
      () async {
    final provider = LogProvider(
      sessionListLoader: () async => [_session(status: 'active')],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    await provider.reloadForSession('history-session');

    expect(provider.currentSessionReadOnly, isFalse);
    provider.dispose();
  });
}

Session _session({required String status}) => Session(
      sessionId: 'history-session',
      title: 'Sunday net',
      status: status,
      createdAt: '2026-07-13T10:00:00Z',
      updatedAt: '2026-07-13T11:00:00Z',
      closedAt: status == 'closed' ? '2026-07-13T11:00:00Z' : null,
    );

bridge.LogEntry _bridgeLog({
  required String id,
  required String time,
  required String rstSent,
  required String rstRcvd,
}) =>
    bridge.LogEntry(
      syncId: id,
      sessionId: 'session',
      time: time,
      controller: 'BG5CRL',
      callsign: 'BG5FBT',
      rstSent: rstSent,
      rstRcvd: rstRcvd,
      createdAt: time,
      updatedAt: time,
    );
