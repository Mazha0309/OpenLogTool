import 'dart:convert';

import 'package:openlogtool/providers/ai_recognition_settings_provider.dart';
import 'package:openlogtool/services/ai_recognition/providers.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

enum DictionaryAiCategory { device, antenna, callsign, qth }

enum DictionaryAiAction { add, rename, merge }

final class DictionaryAiHistoryValue {
  const DictionaryAiHistoryValue({required this.value, required this.count});

  final String value;
  final int count;
}

final class DictionaryAiSource {
  const DictionaryAiSource({
    required this.stateToken,
    required this.recordCount,
    required this.dictionaries,
    required this.history,
  });

  factory DictionaryAiSource.fromJson(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('DICTIONARY_AI_SOURCE_INVALID');
    }
    final json = Map<String, Object?>.from(decoded);
    final dictionaryJson = json['dictionaries'];
    final historyJson = json['history'];
    if (dictionaryJson is! Map || historyJson is! Map) {
      throw const FormatException('DICTIONARY_AI_SOURCE_INVALID');
    }
    final dictionaries = <DictionaryAiCategory, List<String>>{};
    final history = <DictionaryAiCategory, List<DictionaryAiHistoryValue>>{};
    for (final category in DictionaryAiCategory.values) {
      final rawDictionary = dictionaryJson[category.name];
      if (rawDictionary is! List) {
        throw const FormatException('DICTIONARY_AI_SOURCE_INVALID');
      }
      dictionaries[category] = <String>[
        for (final item in rawDictionary)
          if (item is Map && item['value'] is String)
            (item['value'] as String).trim(),
      ]..removeWhere((item) => item.isEmpty);

      final rawHistory = historyJson[category.name];
      if (rawHistory is! List) {
        throw const FormatException('DICTIONARY_AI_SOURCE_INVALID');
      }
      history[category] = <DictionaryAiHistoryValue>[
        for (final item in rawHistory)
          if (item is Map &&
              item['value'] is String &&
              item['count'] is num &&
              (item['value'] as String).trim().isNotEmpty)
            DictionaryAiHistoryValue(
              value: (item['value'] as String).trim(),
              count: (item['count'] as num).toInt(),
            ),
      ];
    }
    return DictionaryAiSource(
      stateToken: json['stateToken']?.toString() ?? '',
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      dictionaries: Map.unmodifiable(dictionaries),
      history: Map.unmodifiable(history),
    );
  }

  final String stateToken;
  final int recordCount;
  final Map<DictionaryAiCategory, List<String>> dictionaries;
  final Map<DictionaryAiCategory, List<DictionaryAiHistoryValue>> history;
}

final class DictionaryAiSuggestion {
  const DictionaryAiSuggestion({
    required this.category,
    required this.action,
    required this.target,
    required this.reason,
    this.source,
    this.evidenceCount = 0,
  });

  final DictionaryAiCategory category;
  final DictionaryAiAction action;
  final String? source;
  final String target;
  final String reason;
  final int evidenceCount;

  String get id => '${category.name}:${action.name}:${source ?? ''}:$target';

  Map<String, Object?> toApplyJson() {
    final generated = DictionaryPinyinHelper.generate(target);
    return <String, Object?>{
      'action': action.name,
      'dictType': '${category.name}_dictionary',
      if (source != null) 'source': source,
      'target': target,
      if (action != DictionaryAiAction.merge) 'pinyin': generated.pinyin,
      if (action != DictionaryAiAction.merge)
        'abbreviation': generated.abbreviation,
    };
  }
}

typedef TextAssistantProgress = void Function(int completed, int total);
const int _dictionaryAiBatchSize = 40;
typedef InlineTextSuggestionExecutor = Future<String?> Function({
  required AiRecognitionSettingsProvider settings,
  required String field,
  required String value,
  List<String> localReferences,
  AiCancellationToken? cancellationToken,
});

abstract final class TextAssistantTasks {
  static const _inlineSystemPrompt = '''
You normalize one amateur-radio log form value. Return only JSON:
{"suggestion":"..."}
Never invent information or add details not present in the input. Return the
original value when no safe normalization is possible. Use concise conventional
formatting. Power should use a number plus W when a numeric watt value is
explicit. Preserve floor/height meaning and units.
''';

  static Future<String?> suggestInline({
    required AiRecognitionSettingsProvider settings,
    required String field,
    required String value,
    List<String> localReferences = const <String>[],
    AiCancellationToken? cancellationToken,
  }) async {
    await settings.initialized;
    final normalized = value.trim();
    if (!settings.textAssistantEnabled || normalized.isEmpty) return null;
    final client = settings.createTextAssistantClient(
      timeout: const Duration(seconds: 12),
    );
    try {
      final result = await client.completeJson(
        systemPrompt: _inlineSystemPrompt,
        userPrompt: jsonEncode(<String, Object?>{
          'field': field,
          'value': normalized,
          if (localReferences.isNotEmpty)
            'nearbyLocalTerms': localReferences.take(8).toList(),
        }),
        cancellationToken: cancellationToken,
        maxOutputTokens: 80,
      );
      final suggestion = result['suggestion'];
      if (suggestion is! String) return null;
      final candidate = suggestion.trim();
      if (candidate.isEmpty ||
          candidate == normalized ||
          candidate.length > 120) {
        return null;
      }
      return candidate;
    } finally {
      client.close();
    }
  }

  static Future<List<DictionaryAiSuggestion>> recognizeHistory({
    required AiRecognitionSettingsProvider settings,
    required DictionaryAiSource source,
    AiCancellationToken? cancellationToken,
    TextAssistantProgress? onProgress,
  }) async {
    final jobs = <({
      DictionaryAiCategory category,
      List<DictionaryAiHistoryValue> values
    })>[];
    for (final category in DictionaryAiCategory.values) {
      final existing = source.dictionaries[category]!.toSet();
      final missing = source.history[category]!
          .where((item) => !existing.contains(item.value))
          .toList(growable: false);
      for (var start = 0;
          start < missing.length;
          start += _dictionaryAiBatchSize) {
        jobs.add((
          category: category,
          values: missing.sublist(
            start,
            (start + _dictionaryAiBatchSize).clamp(0, missing.length),
          ),
        ));
      }
    }
    final result = <String, DictionaryAiSuggestion>{};
    var completed = 0;
    onProgress?.call(0, jobs.length);
    for (final job in jobs) {
      cancellationToken?.throwIfCancelled(providerId: 'text-assistant');
      final client = settings.createTextAssistantClient(
        timeout: const Duration(seconds: 40),
      );
      try {
        final response = await client.completeJson(
          systemPrompt: _historyPrompt(job.category),
          userPrompt: jsonEncode(<String, Object?>{
            'category': job.category.name,
            'existingTerms': source.dictionaries[job.category],
            'observedValues': <Object?>[
              for (final item in job.values)
                <String, Object?>{'value': item.value, 'count': item.count},
            ],
          }),
          cancellationToken: cancellationToken,
          maxOutputTokens: 1800,
        );
        for (final suggestion in _parseHistorySuggestions(
          response,
          job.category,
          job.values,
          source.dictionaries[job.category]!,
        )) {
          result[suggestion.id] = suggestion;
        }
      } finally {
        client.close();
      }
      completed += 1;
      onProgress?.call(completed, jobs.length);
    }
    return result.values.toList(growable: false);
  }

  static Future<List<DictionaryAiSuggestion>> optimizeDictionaries({
    required AiRecognitionSettingsProvider settings,
    required DictionaryAiSource source,
    AiCancellationToken? cancellationToken,
    TextAssistantProgress? onProgress,
  }) async {
    final categories = DictionaryAiCategory.values
        .where((category) => source.dictionaries[category]!.isNotEmpty)
        .toList(growable: false);
    final jobs = <({
      DictionaryAiCategory category,
      List<String> candidateSources,
    })>[];
    for (final category in categories) {
      final terms = source.dictionaries[category]!;
      for (var start = 0;
          start < terms.length;
          start += _dictionaryAiBatchSize) {
        jobs.add((
          category: category,
          candidateSources: terms.sublist(
            start,
            (start + _dictionaryAiBatchSize).clamp(0, terms.length),
          ),
        ));
      }
    }
    final result = <String, DictionaryAiSuggestion>{};
    var completed = 0;
    onProgress?.call(0, jobs.length);
    for (final job in jobs) {
      cancellationToken?.throwIfCancelled(providerId: 'text-assistant');
      final client = settings.createTextAssistantClient(
        timeout: const Duration(seconds: 45),
      );
      try {
        final response = await client.completeJson(
          systemPrompt: _optimizationPrompt(job.category),
          userPrompt: jsonEncode(<String, Object?>{
            'category': job.category.name,
            'candidateSources': job.candidateSources,
            'dictionaryTerms': source.dictionaries[job.category],
            'usage': <Object?>[
              for (final item in source.history[job.category]!)
                <String, Object?>{'value': item.value, 'count': item.count},
            ],
          }),
          cancellationToken: cancellationToken,
          maxOutputTokens: 2200,
        );
        for (final suggestion in _parseOptimizationSuggestions(
          response,
          job.category,
          source,
          job.candidateSources,
        )) {
          result[suggestion.id] = suggestion;
        }
      } finally {
        client.close();
      }
      completed += 1;
      onProgress?.call(completed, jobs.length);
    }
    return result.values.toList(growable: false);
  }
}

String _historyPrompt(DictionaryAiCategory category) => '''
You review structured historical amateur-radio ${category.name} values and
propose safe dictionary additions. Return only JSON:
{"suggestions":[{"source":"observed exact value","target":"canonical value","reason":"short reason"}]}
Every source must exactly match one observed value. Do not invent a term.
Omit uncertain, sentence-like, placeholder, or malformed values. A target may
only normalize spelling, casing, spacing, punctuation, or a conventional model
name. Do not return values already present in existingTerms.
${_categorySafetyRules(category)}
''';

String _optimizationPrompt(DictionaryAiCategory category) => '''
You optimize one existing amateur-radio ${category.name} dictionary. Return only JSON:
{"suggestions":[{"action":"rename|merge","source":"existing exact term","target":"term","reason":"short reason"}]}
Every source must exactly exist. For rename, target must not already exist and
may only normalize spelling, casing, spacing, punctuation, or conventional
notation. For merge, target must be another exact existing term. Never propose
standalone deletion and never invent equipment, locations, antennas, or callsigns.
Only propose changes whose source appears in candidateSources. Use usage counts
only as supporting evidence.
${_categorySafetyRules(category)}
''';

String _categorySafetyRules(DictionaryAiCategory category) =>
    category == DictionaryAiCategory.qth
        ? '''
QTH values are detailed factual locations, not labels to generalize. Preserve
every administrative area, town, street, village, community, building,
institution, repeater site, landmark, floor, and other location component.
Never shorten a QTH to its city, district, county, town, station, or other parent
area. Never remove a prefix or a suffix such as a city/district name, university
town, hospital, service area, subway/rail station, building, mountain, or site.
The target must retain the complete original place and may differ only in case,
spacing, or punctuation. If that is not possible, omit the suggestion.
'''
        : '';

List<DictionaryAiSuggestion> _parseHistorySuggestions(
  Map<String, Object?> response,
  DictionaryAiCategory category,
  List<DictionaryAiHistoryValue> observed,
  List<String> existing,
) {
  final raw = response['suggestions'];
  if (raw is! List) return const <DictionaryAiSuggestion>[];
  final observedByValue = <String, DictionaryAiHistoryValue>{
    for (final item in observed) item.value: item,
  };
  final existingSet = existing.toSet();
  final result = <DictionaryAiSuggestion>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final source = item['source']?.toString().trim() ?? '';
    final target = item['target']?.toString().trim() ?? '';
    final evidence = observedByValue[source];
    if (evidence == null ||
        target.isEmpty ||
        target.length > 120 ||
        existingSet.contains(target) ||
        !_preservesQthDetail(category, source, target) ||
        !_validCategoryValue(category, target)) {
      continue;
    }
    result.add(DictionaryAiSuggestion(
      category: category,
      action: DictionaryAiAction.add,
      source: source,
      target: target,
      reason: item['reason']?.toString().trim() ?? '',
      evidenceCount: evidence.count,
    ));
  }
  return result;
}

List<DictionaryAiSuggestion> _parseOptimizationSuggestions(
  Map<String, Object?> response,
  DictionaryAiCategory category,
  DictionaryAiSource source,
  List<String> candidateSources,
) {
  final raw = response['suggestions'];
  if (raw is! List) return const <DictionaryAiSuggestion>[];
  final existing = source.dictionaries[category]!.toSet();
  final usage = <String, int>{
    for (final item in source.history[category]!) item.value: item.count,
  };
  final allowedSources = candidateSources.toSet();
  final result = <DictionaryAiSuggestion>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final action = switch (item['action']?.toString()) {
      'rename' => DictionaryAiAction.rename,
      'merge' => DictionaryAiAction.merge,
      _ => null,
    };
    final sourceValue = item['source']?.toString().trim() ?? '';
    final target = item['target']?.toString().trim() ?? '';
    if (action == null ||
        !existing.contains(sourceValue) ||
        !allowedSources.contains(sourceValue) ||
        sourceValue == target ||
        target.isEmpty ||
        target.length > 120 ||
        !_preservesQthDetail(category, sourceValue, target) ||
        !_validCategoryValue(category, target)) {
      continue;
    }
    if (action == DictionaryAiAction.rename && existing.contains(target)) {
      continue;
    }
    if (action == DictionaryAiAction.merge && !existing.contains(target)) {
      continue;
    }
    result.add(DictionaryAiSuggestion(
      category: category,
      action: action,
      source: sourceValue,
      target: target,
      reason: item['reason']?.toString().trim() ?? '',
      evidenceCount: usage[sourceValue] ?? 0,
    ));
  }
  return result;
}

bool _preservesQthDetail(
  DictionaryAiCategory category,
  String source,
  String target,
) {
  if (category != DictionaryAiCategory.qth) return true;
  return _qthFormattingKey(source) == _qthFormattingKey(target);
}

String _qthFormattingKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\-‐‑‒–—―_.,，。、/\\·:：;；()（）\[\]【】]+'), '');

bool _validCategoryValue(DictionaryAiCategory category, String value) {
  if (RegExp(r'[\r\n\t]').hasMatch(value)) return false;
  if (category != DictionaryAiCategory.callsign) return true;
  return RegExp(r'^[A-Za-z0-9/]{3,20}$').hasMatch(value);
}
