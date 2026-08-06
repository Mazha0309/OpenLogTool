import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/controller_display_screen.dart';
import 'package:openlogtool/screens/session_hub_page.dart';
import 'package:openlogtool/services/web_controller_bridge.dart'
    if (dart.library.io) 'package:openlogtool/services/web_controller_bridge_stub.dart'
    as web_bridge;
import 'package:provider/provider.dart';

/// Web 主控屏独立标签页（?page=controller）。
///
/// 首次打开从数据库读取会话数据渲染；之后由主窗口通过
/// BroadcastChannel 推送实时显示数据。
class WebControllerTabPage extends StatefulWidget {
  const WebControllerTabPage({super.key});

  @override
  State<WebControllerTabPage> createState() => _WebControllerTabPageState();
}

class _WebControllerTabPageState extends State<WebControllerTabPage> {
  ControllerDisplayDto? _pushedData;

  @override
  void initState() {
    super.initState();
    _restoreSessionFromUrl();
    if (kIsWeb) {
      web_bridge.listenControllerDisplay(onData: (data) {
        if (mounted) setState(() => _pushedData = data);
      });
    }
  }

  /// 新标签页是全新应用实例：按 URL 的 session 参数恢复会话，
  /// 否则主控屏没有数据可显示。
  Future<void> _restoreSessionFromUrl() async {
    final sessionId = web_bridge.controllerTabSessionId();
    if (sessionId == null || sessionId.isEmpty) return;
    final sessions = context.read<SessionProvider>();
    final logs = context.read<LogProvider>();
    try {
      await logs.reloadForSession(sessionId, propagateErrors: true);
      await sessions.switchToSession(sessionId);
    } catch (e) {
      debugPrint('[WebControllerTabPage] session restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().currentSession;
    final logs = context.watch<LogProvider>();
    final collaboration = context.watch<CollaborationProvider>();
    final settings = context.watch<SettingsProvider>();

    final data = _pushedData ??
        (session == null
            ? null
            : SessionHubPage.displayDataFor(
                session.title,
                logs,
                collaboration,
              ));

    if (data == null) {
      return Scaffold(
        body: Center(
          child: Text(context.l10n.noCurrentSessionHint),
        ),
      );
    }

    return ControllerDisplayScreen(
      data: data,
      preferences: settings.controllerDisplayPreferences,
      onPreferencesChanged: settings.setControllerDisplayPreferences,
      showCloseButton: false,
    );
  }
}
