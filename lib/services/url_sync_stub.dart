import 'package:openlogtool/services/url_sync.dart';

/// dart:io 平台的占位实现。
/// URL 同步仅在 Web 端生效，此分支不应被调用。
void urlSyncInit(void Function(SyncRoute route) onRouteChanged) {}

void urlSyncPush(String page, String? session) {}
