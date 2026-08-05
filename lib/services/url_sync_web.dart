import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:openlogtool/services/url_sync.dart';

/// Web 端浏览器 URL 同步实现。
void urlSyncInit(void Function(SyncRoute route) onRouteChanged) {
  onRouteChanged(parseSyncQuery(web.window.location.search));
  web.window.addEventListener(
      'popstate',
      (web.Event e) {
        onRouteChanged(parseSyncQuery(web.window.location.search));
      }.toJS);
}

void urlSyncPush(String page, String? session) {
  web.window.history.pushState(null, '', buildSyncQuery(page, session));
}
