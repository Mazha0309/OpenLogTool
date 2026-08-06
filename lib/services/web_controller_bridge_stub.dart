import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/services/url_sync.dart' show buildSyncQuery;

/// 桌面/移动端占位：Web 主控屏桥接在这些平台为 no-op。
/// controllerTabUrl 是纯函数，保留真实 URL 以便测试。
const String controllerBroadcastChannelName = 'openlogtool-controller';

bool isControllerTabRoute() => false;

({bool isController, String? sessionId}) controllerTabRouteSnapshot() =>
    (isController: false, sessionId: null);

String? controllerTabSessionId() => null;

String controllerTabUrl(String sessionId) =>
    buildSyncQuery('controller', sessionId);

void openWebControllerTab(String sessionId) {}

void pushControllerDisplay(ControllerDisplayDto data) {}

void listenControllerDisplay({
  required void Function(ControllerDisplayDto data) onData,
}) {}
