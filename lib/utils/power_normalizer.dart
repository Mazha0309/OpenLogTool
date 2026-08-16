/// 功率字段规范化。
///
/// 规则：去掉首尾空白后为纯数字（整数或小数）时补上单位 W；
/// 其余情况（已带 W、带其他字母、含中文、空值）原样返回。
/// 例：50 → 50W、50.5 → 50.5W、50W/5kW/500mW/50瓦/50 瓦 → 不变。
String normalizePower(String raw) {
  final trimmed = raw.trim();
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) {
    return '${trimmed}W';
  }
  return trimmed;
}
