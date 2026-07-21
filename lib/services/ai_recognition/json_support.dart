import 'dart:convert';

import 'models.dart';

Object? readAiJsonPath(Object? value, String path) {
  final tokens = _parsePath(path);
  var current = value;
  for (final token in tokens) {
    if (token is int) {
      if (current is! List || token < 0 || token >= current.length) {
        throw FormatException('JSON path not found: $path');
      }
      current = current[token];
      continue;
    }
    if (current is! Map || !current.containsKey(token)) {
      throw FormatException('JSON path not found: $path');
    }
    current = current[token];
  }
  return current;
}

Object? renderAiJsonTemplate(
  Object? template,
  AiJsonObject variables,
) {
  if (template == null || template is num || template is bool) return template;
  if (template is List) {
    return template
        .map((value) => renderAiJsonTemplate(value, variables))
        .toList(growable: false);
  }
  if (template is Map) {
    final result = <String, Object?>{};
    for (final entry in template.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON template keys must be strings');
      }
      result[entry.key as String] = renderAiJsonTemplate(
        entry.value,
        variables,
      );
    }
    return result;
  }
  if (template is! String) {
    throw const FormatException('Template contains a non-JSON value');
  }

  final exact = RegExp(r'^\{\{\s*([^{}]+?)\s*\}\}$').firstMatch(template);
  if (exact != null) {
    return _copyJsonValue(readAiJsonPath(variables, exact.group(1)!));
  }

  return template.replaceAllMapped(
    RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'),
    (match) {
      final replacement = readAiJsonPath(variables, match.group(1)!);
      if (replacement == null) return '';
      if (replacement is String || replacement is num || replacement is bool) {
        return replacement.toString();
      }
      return jsonEncode(replacement);
    },
  );
}

List<Object> _parsePath(String value) {
  var path = value.trim();
  if (path.isEmpty || path == r'$') return const [];
  if (path.startsWith(r'$')) path = path.substring(1);

  final result = <Object>[];
  var index = 0;
  while (index < path.length) {
    if (path[index] == '.') {
      index += 1;
      continue;
    }
    if (path[index] == '[') {
      final end = path.indexOf(']', index + 1);
      if (end < 0) throw FormatException('Invalid JSON path: $value');
      var token = path.substring(index + 1, end).trim();
      if ((token.startsWith('"') && token.endsWith('"')) ||
          (token.startsWith("'") && token.endsWith("'"))) {
        token = token.substring(1, token.length - 1);
        result.add(token);
      } else {
        final listIndex = int.tryParse(token);
        if (listIndex == null) {
          throw FormatException('Invalid JSON path index: $token');
        }
        result.add(listIndex);
      }
      index = end + 1;
      continue;
    }

    var end = index;
    while (end < path.length && path[end] != '.' && path[end] != '[') {
      end += 1;
    }
    final token = path.substring(index, end).trim();
    if (token.isEmpty) throw FormatException('Invalid JSON path: $value');
    result.add(token);
    index = end;
  }
  return result;
}

Object? _copyJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_copyJsonValue).toList(growable: false);
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String)
          entry.key as String: _copyJsonValue(entry.value),
    };
  }
  throw const FormatException('Value is not JSON-compatible');
}
