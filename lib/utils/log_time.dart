/// Resolves the value captured by one save operation.
///
/// A manual clock value remains editable as `HH:mm`. An empty field is
/// represented by one canonical UTC timestamp so local, online collaboration,
/// and offline-queue paths all retain the same second-precision instant.
String resolveLogTimeForSubmission(
  String value, {
  DateTime? capturedAt,
}) {
  final normalized = value.trim();
  if (normalized.isNotEmpty) return normalized;
  return (capturedAt ?? DateTime.now()).toUtc().toIso8601String();
}

String normalizeLogTimeForStorage(
  String value, {
  DateTime? reference,
}) {
  final normalized = value.trim();
  final parsedTimestamp = _tryParseIsoTimestamp(normalized);
  if (parsedTimestamp != null) {
    return parsedTimestamp.toUtc().toIso8601String();
  }

  final match = _clockTimePattern.firstMatch(normalized);
  if (match != null) {
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.parse(match.group(3) ?? '0');
    if (hour <= 23 && minute <= 59 && second <= 59) {
      final localReference = (reference ?? DateTime.now()).toLocal();
      return DateTime(
        localReference.year,
        localReference.month,
        localReference.day,
        hour,
        minute,
        second,
      ).toUtc().toIso8601String();
    }
  }

  if (normalized.isEmpty) {
    return (reference ?? DateTime.now()).toUtc().toIso8601String();
  }
  return normalized;
}

String formatLogTimeForDisplay(
  String value, {
  bool includeDate = false,
}) {
  final normalized = value.trim();
  final parsedTimestamp = _tryParseIsoTimestamp(normalized);
  if (parsedTimestamp != null) {
    final local = parsedTimestamp.toLocal();
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    if (!includeDate) return time;
    return '${local.year.toString().padLeft(4, '0')}-'
        '${_twoDigits(local.month)}-${_twoDigits(local.day)} $time';
  }

  final match = _clockTimePattern.firstMatch(normalized);
  if (match != null) {
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour != null && minute != null && hour <= 23 && minute <= 59) {
      return '${_twoDigits(hour)}:${_twoDigits(minute)}';
    }
  }
  return normalized;
}

bool isValidLogTimeInput(String value, {bool allowEmpty = false}) {
  final normalized = value.trim();
  if (normalized.isEmpty) return allowEmpty;
  if (_tryParseIsoTimestamp(normalized) != null) return true;
  final match = _clockTimePattern.firstMatch(normalized);
  if (match == null) return false;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  final second = int.tryParse(match.group(3) ?? '0');
  return hour != null &&
      minute != null &&
      second != null &&
      hour <= 23 &&
      minute <= 59 &&
      second <= 59;
}

final RegExp _clockTimePattern = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');
final RegExp _isoTimestampPattern =
    RegExp(r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}');

DateTime? _tryParseIsoTimestamp(String value) {
  if (!_isoTimestampPattern.hasMatch(value)) return null;
  final parseable = value.length > 10 && value[10] == 't'
      ? value.replaceRange(10, 11, 'T')
      : value;
  return DateTime.tryParse(parseable);
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
