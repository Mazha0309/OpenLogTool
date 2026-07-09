import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

void main() {
  group('DictionaryPinyinHelper', () {
    test('Chinese + model: 华鸿 S518', () {
      final result = DictionaryPinyinHelper.generate('华鸿 S518');
      expect(result.pinyin, 'huahong s518');
      expect(result.abbreviation, 'hhs518');
    });

    test('English + digits: ICOM 7300', () {
      final result = DictionaryPinyinHelper.generate('ICOM 7300');
      expect(result.pinyin, 'icom 7300');
      expect(result.abbreviation, 'icom7300');
    });

    test('Chinese + model with hyphen: 钻石 X-50', () {
      final result = DictionaryPinyinHelper.generate('钻石 X-50');
      expect(result.pinyin, 'zuanshi x-50');
      expect(result.abbreviation, 'zsx50');
    });

    test('Chinese + number + Chinese suffix: 华鸿 1.2米玻璃钢', () {
      final result = DictionaryPinyinHelper.generate('华鸿 1.2米玻璃钢');
      expect(result.pinyin, 'huahong 1.2miboligang');
      expect(result.abbreviation, 'hh1.2mblg');
    });

    test('Number prefix + Chinese: 771天线', () {
      final result = DictionaryPinyinHelper.generate('771天线');
      expect(result.pinyin, '771tianxian');
      expect(result.abbreviation, '771tx');
    });

    test('Letter/number prefix + Chinese: R2天线', () {
      final result = DictionaryPinyinHelper.generate('R2天线');
      expect(result.pinyin, 'r2tianxian');
      expect(result.abbreviation, 'r2tx');
    });

    test('Empty input returns empty strings', () {
      final result = DictionaryPinyinHelper.generate('');
      expect(result.pinyin, '');
      expect(result.abbreviation, '');
    });

    test('Whitespace-only input returns empty strings', () {
      final result = DictionaryPinyinHelper.generate('   ');
      expect(result.pinyin, '');
      expect(result.abbreviation, '');
    });
  });
}
