import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;

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
}

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
