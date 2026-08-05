import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/excel_import_service.dart';

void main() {
  test('validateLlmOutput keeps valid records and uppercases callsign', () {
    final output = validateLlmOutput([
      {
        'callsign': 'bg5fbt',
        'qth': '杭州',
        'time': '12:30',
      },
      {
        'callsign': '',
        'qth': '缺呼号',
      },
      'not-a-map',
      {
        'callsign': '  ',
      },
      {
        'callsign': 'BG7XYZ',
        'power': 50,
      },
    ]);
    expect(output, hasLength(2));
    expect(output[0]['callsign'], 'BG5FBT');
    expect(output[0]['qth'], '杭州');
    expect(output[1]['callsign'], 'BG7XYZ');
    expect(output[1]['power'], '50');
  });

  test('validateLlmOutput rejects non-list input', () {
    expect(validateLlmOutput(null), isEmpty);
    expect(validateLlmOutput({'records': []}), isEmpty);
  });

  test('buildSheetText renders rows with line numbers', () {
    final text = buildSheetText([
      ['BG5FBT', '杭州', '59'],
      ['BG7XYZ'],
    ]);
    expect(text, contains('1: BG5FBT | 杭州 | 59'));
    expect(text, contains('2: BG7XYZ'));
  });

  test('buildSheetText handles empty rows', () {
    expect(buildSheetText([]), isEmpty);
  });
}
