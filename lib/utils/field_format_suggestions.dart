final RegExp _plainNumber = RegExp(r'^\d+(?:\.\d+)?$');

/// Local, deterministic unit candidates used by the net-control form.
///
/// Only a plain number is expanded. Descriptive values such as `地面`,
/// `高架`, `中功率`, and `高功率` remain untouched and do not open this menu.
List<String> fieldFormatSuggestions(String field, String raw) {
  final value = raw.trim();
  if (!_plainNumber.hasMatch(value)) return const <String>[];
  return switch (field) {
    'power' => <String>['${value}W', value],
    'height' => <String>['$value楼', '$value米'],
    _ => const <String>[],
  };
}

bool containsCjkText(String raw) =>
    RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]').hasMatch(raw);
