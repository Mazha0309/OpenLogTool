import 'package:openlogtool/services/deployed_config_stub.dart'
    show defaultServerUrlFromMeta;
import 'package:web/web.dart' as web;

/// 部署注入的默认服务器地址（Web）。
///
/// 由部署方在 index.html 的 meta[name=openlogtool-default-server] 中注入；
/// 未注入或仍是占位符时返回 null。
String? deployedDefaultServerUrl() {
  final meta = web.document.querySelector(
    'meta[name="openlogtool-default-server"]',
  );
  final content = meta?.getAttribute('content');
  return defaultServerUrlFromMeta(content);
}
