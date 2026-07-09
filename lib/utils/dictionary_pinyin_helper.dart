import 'package:lpinyin/lpinyin.dart';

class PinyinResult {
  final String pinyin;
  final String abbreviation;

  const PinyinResult({required this.pinyin, required this.abbreviation});
}

class DictionaryPinyinHelper {
  static PinyinResult generate(String raw) {
    if (raw.trim().isEmpty) {
      return const PinyinResult(pinyin: '', abbreviation: '');
    }
    try {
      final pinyin = PinyinHelper.getPinyinE(
        raw,
        separator: ' ',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase();
      final abbreviation = PinyinHelper.getShortPinyin(raw).toLowerCase();
      return PinyinResult(pinyin: pinyin, abbreviation: abbreviation);
    } catch (_) {
      final fallback = raw.toLowerCase();
      return PinyinResult(pinyin: fallback, abbreviation: fallback);
    }
  }
}
