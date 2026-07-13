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
      final tokens = raw.trim().split(RegExp(r'\s+'));

      final pinyinParts = <String>[];
      final abbreviationParts = <String>[];

      for (final token in tokens) {
        final pinyin = PinyinHelper.getPinyinE(
          token,
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase();
        pinyinParts.add(pinyin);

        final abbreviation = PinyinHelper.getShortPinyin(
          token,
        ).toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
        abbreviationParts.add(abbreviation);
      }

      return PinyinResult(
        pinyin: pinyinParts.join(' '),
        abbreviation: abbreviationParts.join(),
      );
    } catch (_) {
      final fallbackPinyin = raw.toLowerCase();
      final fallbackAbbreviation = raw.toLowerCase().replaceAll(
        RegExp(r'\s+'),
        '',
      );
      return PinyinResult(
        pinyin: fallbackPinyin,
        abbreviation: fallbackAbbreviation,
      );
    }
  }
}
