import 'package:openlogtool/models/controller_display.dart';

/// 桌面/移动端占位：Web 主控屏桥接在这些平台为 no-op。
const String controllerBroadcastChannelName = 'openlogtool-controller';

String controllerTabUrl(String sessionId) => '';

void openWebControllerTab(String sessionId) {}

void pushControllerDisplay(ControllerDisplayDto data) {}

void listenControllerDisplay({
  required void Function(ControllerDisplayDto data) onData,
}) {}
