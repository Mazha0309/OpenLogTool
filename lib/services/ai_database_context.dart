import 'dart:convert';

import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

/// Builds a small, transcript-specific glossary for the field extraction
/// model. The complete local database is never included.
abstract final class AiDatabaseContextBuilder {
  static const int _maxItemsPerCategory = 8;
  static const int _maxRecentRecords = 6;

  static String? build({
    required String transcript,
    required List<DictionaryItem> devices,
    required List<DictionaryItem> antennas,
    required List<DictionaryItem> callsigns,
    required List<DictionaryItem> qths,
    required List<LogEntry> recentLogs,
  }) {
    final normalized = _normalized(transcript);
    if (normalized.isEmpty) return null;
    final transcriptPinyin = _normalized(
      DictionaryPinyinHelper.generate(transcript).pinyin,
    );
    final natoCandidates = _natoCandidates(transcript);

    final selectedCallsigns = _rank(
      callsigns,
      (item) => _callsignScore(item.raw, normalized, natoCandidates),
    );
    final selectedDevices = _rankTerms(devices, normalized, transcriptPinyin);
    final selectedAntennas = _rankTerms(
      antennas,
      normalized,
      transcriptPinyin,
    );
    final selectedQths = _rankTerms(qths, normalized, transcriptPinyin);

    final knownCallsigns = <String>{
      for (final item in selectedCallsigns) _normalized(item.raw),
    };
    final selectedRecords = recentLogs.reversed
        .where((log) {
          final callsign = _normalized(log.callsign);
          return callsign.isNotEmpty &&
              (knownCallsigns.contains(callsign) ||
                  _callsignScore(log.callsign, normalized, natoCandidates) > 0);
        })
        .take(_maxRecentRecords)
        .map(_recordReference)
        .toList(growable: false);

    final references = <String, Object>{
      if (selectedCallsigns.isNotEmpty)
        'callsigns': selectedCallsigns.map((item) => item.raw).toList(),
      if (selectedDevices.isNotEmpty)
        'devices': selectedDevices.map((item) => item.raw).toList(),
      if (selectedAntennas.isNotEmpty)
        'antennas': selectedAntennas.map((item) => item.raw).toList(),
      if (selectedQths.isNotEmpty)
        'qths': selectedQths.map((item) => item.raw).toList(),
      if (selectedRecords.isNotEmpty) 'recentRecords': selectedRecords,
    };
    if (references.isEmpty) return null;
    return const JsonEncoder.withIndent('  ').convert(references);
  }

  static List<DictionaryItem> _rankTerms(
    List<DictionaryItem> items,
    String transcript,
    String transcriptPinyin,
  ) =>
      _rank(
        items,
        (item) => _termScore(item, transcript, transcriptPinyin),
      );

  static List<DictionaryItem> _rank(
    List<DictionaryItem> items,
    int Function(DictionaryItem item) score,
  ) {
    final scored = <({DictionaryItem item, int score})>[];
    for (final item in items) {
      final value = score(item);
      if (value > 0 && item.raw.trim().isNotEmpty) {
        scored.add((item: item, score: value));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.item.raw.compareTo(b.item.raw);
    });
    return scored
        .take(_maxItemsPerCategory)
        .map((value) => value.item)
        .toList(growable: false);
  }

  static int _termScore(
    DictionaryItem item,
    String transcript,
    String transcriptPinyin,
  ) {
    final raw = _normalized(item.raw);
    final pinyin = _normalized(item.pinyin.isEmpty
        ? DictionaryPinyinHelper.generate(item.raw).pinyin
        : item.pinyin);
    final abbreviation = _normalized(item.abbreviation);
    var score = 0;
    if (raw.length >= 2 && transcript.contains(raw)) {
      score = 120 + raw.length;
    }
    if (pinyin.length >= 4 && transcriptPinyin.contains(pinyin)) {
      score = score < 100 + pinyin.length ? 100 + pinyin.length : score;
    }
    if (abbreviation.length >= 3 && transcript.contains(abbreviation)) {
      score =
          score < 70 + abbreviation.length ? 70 + abbreviation.length : score;
    }
    if (raw.length >= 3) {
      final mixedModelName = RegExp(r'[a-z0-9]').hasMatch(raw);
      final permittedDistance = mixedModelName && raw.length >= 4 ? 2 : 1;
      final distance = _closestWindowDistance(raw, transcript);
      if (distance <= permittedDistance) {
        final fuzzyScore = 60 + raw.length - distance * 8;
        if (fuzzyScore > score) score = fuzzyScore;
      }
    }
    return score;
  }

  static int _callsignScore(
    String value,
    String transcript,
    List<String> natoCandidates,
  ) {
    final callsign = _normalized(value).toUpperCase();
    if (callsign.length < 3) return 0;
    if (transcript.toUpperCase().contains(callsign)) {
      return 150 + callsign.length;
    }
    var best = 0;
    for (final candidate in natoCandidates) {
      if (candidate.length < 3) continue;
      final distance = _editDistance(callsign, candidate);
      final permitted = callsign.length <= 5 ? 1 : 2;
      if (distance <= permitted) {
        final score = 110 - distance * 20;
        if (score > best) best = score;
      }
    }
    return best;
  }

  static List<String> _natoCandidates(String transcript) {
    const symbols = <String, String>{
      'alpha': 'A',
      'alfa': 'A',
      'bravo': 'B',
      'charlie': 'C',
      'delta': 'D',
      'echo': 'E',
      'foxtrot': 'F',
      'golf': 'G',
      'hotel': 'H',
      'india': 'I',
      'juliett': 'J',
      'juliet': 'J',
      'kilo': 'K',
      'lima': 'L',
      'mike': 'M',
      'november': 'N',
      'oscar': 'O',
      'papa': 'P',
      'quebec': 'Q',
      'romeo': 'R',
      'sierra': 'S',
      'tango': 'T',
      'uniform': 'U',
      'victor': 'V',
      'whiskey': 'W',
      'xray': 'X',
      'yankee': 'Y',
      'zulu': 'Z',
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
    };
    final words = RegExp(r'[A-Za-z]+|[0-9]')
        .allMatches(transcript)
        .map((match) => match.group(0)!.toLowerCase())
        .toList(growable: false);
    final result = <String>[];
    var current = StringBuffer();
    void flush() {
      final value = current.toString();
      if (value.length >= 3) result.add(value);
      current = StringBuffer();
    }

    for (final word in words) {
      final symbol =
          symbols[word] ?? (word.length == 1 ? word.toUpperCase() : null);
      if (symbol == null) {
        flush();
      } else {
        current.write(symbol);
      }
    }
    flush();
    return result;
  }

  static int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex + 1;
      for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
        final substitution = previous[rightIndex] +
            (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex)
                ? 0
                : 1);
        final insertion = current[rightIndex] + 1;
        final deletion = previous[rightIndex + 1] + 1;
        current[rightIndex + 1] =
            [substitution, insertion, deletion].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  static int _closestWindowDistance(String term, String text) {
    if (text.isEmpty) return term.length;
    var best = term.length;
    final minimumLength = term.length > 2 ? term.length - 2 : 1;
    final maximumLength = term.length + 2;
    for (var length = minimumLength; length <= maximumLength; length += 1) {
      if (length > text.length) continue;
      for (var start = 0; start + length <= text.length; start += 1) {
        final distance = _editDistance(
          term,
          text.substring(start, start + length),
        );
        if (distance < best) best = distance;
        if (best == 0) return 0;
      }
    }
    return best;
  }

  static Map<String, String> _recordReference(LogEntry log) => {
        'callsign': log.callsign,
        if (log.device.trim().isNotEmpty) 'device': log.device,
        if (log.antenna.trim().isNotEmpty) 'antenna': log.antenna,
        if (log.power.trim().isNotEmpty) 'power': log.power,
        if (log.qth.trim().isNotEmpty) 'qth': log.qth,
        if (log.height.trim().isNotEmpty) 'height': log.height,
      };

  static String _normalized(String value) {
    var normalized = value.toLowerCase();
    const chineseDigits = <String, String>{
      '零': '0',
      '〇': '0',
      '一': '1',
      '二': '2',
      '两': '2',
      '三': '3',
      '四': '4',
      '五': '5',
      '六': '6',
      '七': '7',
      '八': '8',
      '九': '9',
    };
    for (final entry in chineseDigits.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }
}
