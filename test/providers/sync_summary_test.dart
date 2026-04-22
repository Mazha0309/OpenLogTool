import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/sync_provider.dart';

void main() {
  group('sync summary helpers', () {
    test('formatSyncSummaryText returns fallback when summary missing', () {
      expect(formatSyncSummaryText(null), '暂无同步结果');
    });

    test('formatSyncSummaryText aggregates applied ignored and conflicts', () {
      final summary = <String, dynamic>{
        'applied': {
          'logs': 2,
          'dictionaries': 1,
          'history': 3,
          'callsignQthHistory': 0,
        },
        'ignored': {
          'logs': 1,
          'dictionaries': 2,
          'history': 0,
          'callsignQthHistory': 1,
        },
        'conflicts': 4,
      };

      expect(syncSummaryGroupTotal(summary, 'applied'), 6);
      expect(syncSummaryGroupTotal(summary, 'ignored'), 4);
      expect(syncSummaryConflicts(summary), 4);
      expect(formatSyncSummaryText(summary), '已应用 6 条，忽略 4 条，冲突 4 条');
    });
  });
}
