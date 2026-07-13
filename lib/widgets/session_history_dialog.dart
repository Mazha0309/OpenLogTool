import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:provider/provider.dart';

typedef SessionHistoryLoader = Future<List<Session>> Function();
typedef SessionHistoryAction = Future<void> Function(Session session);

Future<void> showSessionHistoryDialog(
  BuildContext context, {
  VoidCallback? onSessionOpened,
}) async {
  final sessionProvider = context.read<SessionProvider>();
  final logProvider = context.read<LogProvider>();
  final selected = await showDialog<Session>(
    context: context,
    builder: (_) => SessionHistoryDialog(
      currentSessionId: sessionProvider.currentSessionId,
      loadSessions: sessionProvider.listAvailableSessions,
      openSession: (session) async {
        final previousSessionId = sessionProvider.currentSessionId;
        try {
          // Load the target before persisting it as current. This keeps a
          // failed history open from leaving the two providers out of sync.
          await logProvider.reloadForSession(
            session.sessionId,
            propagateErrors: true,
          );
          await sessionProvider.switchToSession(session.sessionId);
        } catch (error, stackTrace) {
          try {
            await logProvider.reloadForSession(
              previousSessionId,
              propagateErrors: true,
            );
          } catch (rollbackError, rollbackStackTrace) {
            debugPrint(
              '[SessionHistory] log rollback failed: '
              '$rollbackError\n$rollbackStackTrace',
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      },
      closeSession: (session) =>
          logProvider.hardDeleteSession(session.sessionId),
    ),
  );
  if (selected == null || !context.mounted) return;
  onSessionOpened?.call();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
        content: Text(context.l10n.historySessionSwitched(selected.title))),
  );
}

class SessionHistoryDialog extends StatefulWidget {
  const SessionHistoryDialog({
    super.key,
    required this.currentSessionId,
    required this.loadSessions,
    required this.openSession,
    required this.closeSession,
  });

  final String? currentSessionId;
  final SessionHistoryLoader loadSessions;
  final SessionHistoryAction openSession;
  final SessionHistoryAction closeSession;

  @override
  State<SessionHistoryDialog> createState() => _SessionHistoryDialogState();
}

class _SessionHistoryDialogState extends State<SessionHistoryDialog> {
  late Future<List<Session>> _sessions;
  String? _busySessionId;

  @override
  void initState() {
    super.initState();
    _sessions = widget.loadSessions();
  }

  void _reload() {
    setState(() => _sessions = widget.loadSessions());
  }

  Future<void> _open(Session session) async {
    if (_busySessionId != null) return;
    setState(() => _busySessionId = session.sessionId);
    try {
      await widget.openSession(session);
      if (!mounted) return;
      setState(() => _busySessionId = null);
      Navigator.of(context).pop(session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busySessionId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.historySessionOpenFailed(error.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _close(Session session) async {
    if (_busySessionId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.historySessionCloseTitle),
        content: Text(
          context.l10n.historySessionCloseConfirmation(session.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.closeSession),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySessionId = session.sessionId);
    try {
      await widget.closeSession(session);
      if (!mounted) return;
      setState(() {
        _busySessionId = null;
        _sessions = widget.loadSessions();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.historySessionClosed)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busySessionId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.historySessionCloseFailed(error.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return AlertDialog(
      key: const Key('session-history-dialog'),
      title: Text(context.l10n.historySessions),
      content: SizedBox(
        width: 620,
        height: height.clamp(280, 560),
        child: FutureBuilder<List<Session>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n
                          .historySessionsLoadFailed(snapshot.error.toString()),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              );
            }
            final sessions = snapshot.data ?? const <Session>[];
            if (sessions.isEmpty) {
              return Center(child: Text(context.l10n.historySessionsEmpty));
            }
            return ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _sessionTile(sessions[index]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  Widget _sessionTile(Session session) {
    final isCurrent = widget.currentSessionId == session.sessionId;
    final isActive = session.status == 'active';
    final busy = _busySessionId == session.sessionId;
    final createdAt = DateTime.tryParse(session.createdAt)?.toLocal();
    final createdLabel = createdAt == null
        ? session.createdAt
        : '${MaterialLocalizations.of(context).formatMediumDate(createdAt)} '
            '${TimeOfDay.fromDateTime(createdAt).format(context)}';
    return ListTile(
      key: Key('session-history-tile-${session.sessionId}'),
      enabled: !isCurrent && _busySessionId == null,
      onTap: isCurrent || _busySessionId != null ? null : () => _open(session),
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.lock_clock_outlined,
        color: isActive ? Colors.green : null,
      ),
      title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$createdLabel · '
        '${isActive ? context.l10n.sessionActive : context.l10n.sessionClosed}',
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isCurrent
              ? Chip(label: Text(context.l10n.historySessionCurrent))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('open-history-session-${session.sessionId}'),
                      tooltip: context.l10n.historySessionOpen,
                      onPressed:
                          _busySessionId == null ? () => _open(session) : null,
                      icon: const Icon(Icons.open_in_new),
                    ),
                    if (isActive)
                      IconButton(
                        key: Key('close-history-session-${session.sessionId}'),
                        tooltip: context.l10n.closeSession,
                        onPressed: _busySessionId == null
                            ? () => _close(session)
                            : null,
                        icon: Icon(
                          Icons.stop_circle_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
    );
  }
}
