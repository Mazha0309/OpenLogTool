import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/services/ai_database_context.dart';

void main() {
  test('selects phonetic dictionary matches without uploading unrelated rows',
      () {
    final context = AiDatabaseContextBuilder.build(
      transcript: '这里是四穿，使用威讯七。',
      devices: [_item('威诺 N7'), _item('IC-7300')],
      antennas: const [],
      callsigns: const [],
      qths: [_item('四川'), _item('北京')],
      recentLogs: const [],
    );

    expect(context, contains('威诺 N7'));
    expect(context, contains('四川'));
    expect(context, isNot(contains('IC-7300')));
    expect(context, isNot(contains('北京')));
  });

  test('uses a close NATO callsign to select only matching recent records', () {
    final context = AiDatabaseContextBuilder.build(
      transcript: 'Bravo Golf Five Echo Uniform Uniform，低功率，二楼。',
      devices: const [],
      antennas: const [],
      callsigns: const [],
      qths: const [],
      recentLogs: [
        _log(callsign: 'BG5EUU', device: '威诺 N7', qth: '二楼'),
        _log(callsign: 'BA1ZZZ', device: 'IC-705', qth: '北京'),
      ],
    );

    expect(context, contains('BG5EUU'));
    expect(context, contains('威诺 N7'));
    expect(context, contains('二楼'));
    expect(context, isNot(contains('BA1ZZZ')));
    expect(context, isNot(contains('IC-705')));
  });

  test('returns no context when nothing in the database resembles speech', () {
    expect(
      AiDatabaseContextBuilder.build(
        transcript: '嗯，申请上台。',
        devices: [_item('IC-7300')],
        antennas: [_item('八木天线')],
        callsigns: [_item('BG5CRL')],
        qths: [_item('杭州')],
        recentLogs: const [],
      ),
      isNull,
    );
  });
}

DictionaryItem _item(String raw) => DictionaryItem(
      raw: raw,
      pinyin: '',
      abbreviation: '',
    );

LogEntry _log({
  required String callsign,
  required String device,
  required String qth,
}) =>
    LogEntry(
      time: '20:00:00',
      controller: 'BY1ABC',
      callsign: callsign,
      report: '59',
      rstRcvd: '59',
      qth: qth,
      device: device,
      power: '低功率',
      antenna: '拉杆天线',
      height: '二楼',
    );
