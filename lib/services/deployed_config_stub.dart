/// 部署注入的默认服务器地址解析（桌面/移动端与纯函数）。
///
/// 桌面/移动端没有部署注入，返回 null；Web 端由 deployed_config.dart 提供
/// 真正的 meta 读取实现。
library;

/// 部署注入的默认服务器地址；桌面/移动端无注入，返回 null。
String? deployedDefaultServerUrl() => null;

/// 从 meta content 解析默认服务器地址（纯函数，可测试）。
/// 未注入（null/空）或仍是部署占位符时返回 null。
String? defaultServerUrlFromMeta(String? content) {
  final trimmed = content?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (trimmed == '__APP_DEFAULT_SERVER_URL__') return null;
  return trimmed;
}
