import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/field_format_suggestions.dart';

void main() {
  test('offers deterministic unit choices for plain numeric power and height',
      () {
    expect(fieldFormatSuggestions('power', '15'), ['15W', '15']);
    expect(fieldFormatSuggestions('power', ' 15.5 '), ['15.5W', '15.5']);
    expect(fieldFormatSuggestions('height', '5'), ['5楼', '5米']);
  });

  test('does not suggest units for descriptive or already formatted values',
      () {
    for (final value in ['地面', '高架', '中功率', '高功率', '15W', '5楼']) {
      expect(fieldFormatSuggestions('power', value), isEmpty);
      expect(fieldFormatSuggestions('height', value), isEmpty);
    }
  });
}
