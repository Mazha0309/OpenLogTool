import 'dart:convert';
import 'dart:js_interop';

import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/services/url_sync.dart' show buildSyncQuery;
import 'package:web/web.dart' as web;

/// 主控屏数据推送频道名（新标签页与主窗口共享）。
const String controllerBroadcastChannelName = 'openlogtool-controller';

/// 主控屏新标签页 URL（带 page/session 参数，须以 ? 开头否则会被浏览器
/// 当作相对路径）。
String controllerTabUrl(String sessionId) =>
    buildSyncQuery('controller', sessionId);

/// 在主标签页打开主控屏。
void openWebControllerTab(String sessionId) {
  web.window.open(controllerTabUrl(sessionId), '_blank');
}

/// 向主控屏新标签页推送最新显示数据。
void pushControllerDisplay(ControllerDisplayDto data) {
  final channel = web.BroadcastChannel(controllerBroadcastChannelName);
  channel.postMessage(jsonEncode(<String, Object?>{
    'type': 'display',
    'data': data.toJson(),
  }).toJS);
}

/// 新标签页订阅主窗口推送。
void listenControllerDisplay({
  required void Function(ControllerDisplayDto data) onData,
}) {
  final channel = web.BroadcastChannel(controllerBroadcastChannelName);
  channel.onmessage = ((web.MessageEvent event) {
    final raw = event.data;
    final message = raw.dartify();
    if (message is! String) return;
    try {
      final payload = jsonDecode(message);
      if (payload is Map && payload['type'] == 'display') {
        onData(ControllerDisplayDto.fromJson(payload['data']));
      }
    } catch (_) {
      // 忽略无法解析的消息。
    }
  }).toJS;
}
