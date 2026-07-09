import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

void main() {
  group('DictionaryPinyinHelper', () {
    test('generates pinyin and abbreviation for Chinese', () {
      final result = DictionaryPinyinHelper.generate('华鸿 S518');
      expect(result.pinyin, 'hua hong   s 5 1 8');
      expect(result.abbreviation, 'hh s518');
    });

    test('keeps English and digits as-is', () {
      final result = DictionaryPinyinHelper.generate('ICOM 7300');
      expect(result.pinyin, 'i c o m   7 3 0 0');
      expect(result.abbreviation, 'icom 7300');
    });

    test('handles mixed Chinese and model numbers', () {
      final result = DictionaryPinyinHelper.generate('钻石 X-50');
      expect(result.pinyin, 'zuan shi   x - 5 0');
      expect(result.abbreviation, 'zs x-50');
    });

    test('returns empty for empty input', () {
      final result = DictionaryPinyinHelper.generate('');
      expect(result.pinyin, '');
      expect(result.abbreviation, '');
    });
  });
}
