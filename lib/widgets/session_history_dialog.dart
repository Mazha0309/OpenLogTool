import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:provider/provider.dart';

typedef SessionHistoryLoader = Future<List<Session>> Function();
typedef SessionHistoryAction = Future<void> Function(Session session);
typedef SessionCollaborationBindingChecker = Future<bool> Function(
  String sessionId,
);

const _historyCollaborationCloseRequiresOpen =
    'HISTORY_COLLABORATION_CLOSE_REQUIRES_OPEN';
const _historyCollaborationCloseOwnerRequired =
    'HISTORY_COLLABORATION_CLOSE_OWNER_REQUIRED';

String historySessionCloseErrorText(BuildContext context, Object error) {
  final raw = error.toString();
  if (raw.contains(_historyCollaborationCloseRequiresOpen)) {
    return context.l10n.historySessionCollaborationCloseRequiresOpen;
  }
  if (raw.contains(_historyCollaborationCloseOwnerRequired)) {
    return context.l10n.historySessionCollaborationCloseOwnerRequired;
  }
  return context.l10n.historySessionCloseFailed(raw);
}

Future<void> closeSessionFromHistory({
  required Session session,
  required String? currentSessionId,
  required SessionCollaborationBindingChecker hasCollaborationBinding,
  required SessionHistoryAction closeLocalSession,
  required Future<void> Function() refreshCurrentCollaboration,
  required bool Function() canCloseCurrentCollaboration,
  required Future<void> Function() closeCurrentCollaboration,
}) async {
  if (!await hasCollaborationBinding(session.sessionId)) {
    await closeLocalSession(session);
    return;
  }
  if (session.sessionId != currentSessionId) {
    throw StateError(_historyCollaborationCloseRequiresOpen);
  }
  await refreshCurrentCollaboration();
  if (!canCloseCurrentCollaboration()) {
    throw StateError(_historyCollaborationCloseOwnerRequired);
  }
  await closeCurrentCollaboration();
}

String localSessionReopenErrorText(BuildContext context, Object error) {
  final raw = error.toString();
  if (raw.contains('LOCAL_REOPEN_COLLABORATION_FORBIDDEN')) {
    return context.l10n.historySessionCollaborationReopenRequired;
  }
  return context.l10n.historySessionReopenFailed(raw);
}

Future<bool> confirmReopenLocalSession(
  BuildContext context, {
  required String sessionTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.historySessionReopenTitle),
      content: Text(
        dialogContext.l10n.historySessionReopenConfirmation(sessionTitle),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton.icon(
          key: const Key('confirm-reopen-local-session'),
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.play_arrow),
          label: Text(dialogContext.l10n.historySessionReopenAction),
        ),
      ],
    ),
  );
  return confirmed == true;
}

void showReopenedSessionLogsUnavailable(
  BuildContext context, {
  required LogProvider logs,
  required String sessionId,
  required String sessionTitle,
}) {
  if (!context.mounted) return;
  final l10n = context.l10n;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        l10n.historySessionReopenedLogsUnavailable(sessionTitle),
      ),
      action: SnackBarAction(
        label: l10n.retry,
        onPressed: () {
          unawaited(
            _retryReopenedSessionLogs(
              context,
              logs: logs,
              sessionId: sessionId,
              sessionTitle: sessionTitle,
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _retryReopenedSessionLogs(
  BuildContext context, {
  required LogProvider logs,
  required String sessionId,
  required String sessionTitle,
}) async {
  try {
    await logs.reloadForSession(sessionId, propagateErrors: true);
  } catch (_) {
    if (context.mounted) {
      showReopenedSessionLogsUnavailable(
        context,
        logs: logs,
        sessionId: sessionId,
        sessionTitle: sessionTitle,
      );
    }
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.l10n.historySessionSwitched(sessionTitle))),
  );
}

Future<void> showSessionHistoryDialog(
  BuildContext context, {
  VoidCallback? onSessionOpened,
}) async {
  final sessionProvider = context.read<SessionProvider>();
  final logProvider = context.read<LogProvider>();
  final collaborationProvider = context.read<CollaborationProvider>();
  String? reopenedWithoutLogsSessionId;
  Future<void> loadAndSwitch(Session session) async {
    final previousSessionId = sessionProvider.currentSessionId;
    try {
      // Load the target before persisting it as current. This keeps a failed
      // history open from leaving the two providers out of sync.
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
  }

  final selected = await showDialog<Session>(
    context: context,
    builder: (_) => SessionHistoryDialog(
      currentSessionId: sessionProvider.currentSessionId,
      loadSessions: sessionProvider.listAvailableSessions,
      openSession: loadAndSwitch,
      reopenSession: (session) async {
        await sessionProvider.reopenLocalSession(session.sessionId);
        try {
          await logProvider.reloadForSession(
            session.sessionId,
            propagateErrors: true,
          );
        } catch (error, stackTrace) {
          try {
            await sessionProvider.reloadCurrentSession();
          } catch (refreshError, refreshStackTrace) {
            debugPrint(
              '[SessionHistory] reopened session refresh failed: '
              '$refreshError\n$refreshStackTrace',
            );
          }
          reopenedWithoutLogsSessionId = session.sessionId;
          debugPrint(
            '[SessionHistory] reopened session log load failed: '
            '$error\n$stackTrace',
          );
        }
      },
      closeSession: (session) => closeSessionFromHistory(
        session: session,
        currentSessionId: sessionProvider.currentSessionId,
        hasCollaborationBinding: (sessionId) async =>
            await RustApi.getSessionCollaborationBinding(
              sessionId: sessionId,
            ) !=
            null,
        closeLocalSession: (target) =>
            logProvider.closeSession(target.sessionId),
        refreshCurrentCollaboration:
            collaborationProvider.refreshCurrentSession,
        canCloseCurrentCollaboration: () =>
            collaborationProvider.binding?.sessionId == session.sessionId &&
            collaborationProvider.isOwner,
        closeCurrentCollaboration: collaborationProvider.closeCurrentSession,
      ),
      canCloseCurrentSession: collaborationProvider.binding?.sessionId ==
              sessionProvider.currentSessionId &&
          collaborationProvider.isOwner,
      deleteSession: (session) =>
          logProvider.hardDeleteSession(session.sessionId),
    ),
  );
  if (selected == null || !context.mounted) return;
  onSessionOpened?.call();
  if (reopenedWithoutLogsSessionId == selected.sessionId) {
    showReopenedSessionLogsUnavailable(
      context,
      logs: logProvider,
      sessionId: selected.sessionId,
      sessionTitle: selected.title,
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final message = context.l10n.historySessionSwitched(selected.title);
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}

class SessionHistoryDialog extends StatefulWidget {
  const SessionHistoryDialog({
    super.key,
    required this.currentSessionId,
    required this.loadSessions,
    required this.openSession,
    required this.reopenSession,
    required this.closeSession,
    required this.deleteSession,
    this.canCloseCurrentSession = false,
  });

  final String? currentSessionId;
  final SessionHistoryLoader loadSessions;
  final SessionHistoryAction openSession;
  final SessionHistoryAction reopenSession;
  final SessionHistoryAction closeSession;
  final SessionHistoryAction deleteSession;
  final bool canCloseCurrentSession;

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
          content: Text(historySessionCloseErrorText(context, error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _reopen(Session session) async {
    if (_busySessionId != null) return;
    final confirmed = await confirmReopenLocalSession(
      context,
      sessionTitle: session.title,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busySessionId = session.sessionId);
    try {
      await widget.reopenSession(session);
      if (!mounted) return;
      setState(() => _busySessionId = null);
      Navigator.of(context).pop(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busySessionId = null;
        _sessions = widget.loadSessions();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localSessionReopenErrorText(context, error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _delete(Session session) async {
    if (_busySessionId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteSessionConfirmationDialog(
        sessionTitle: session.title,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySessionId = session.sessionId);
    try {
      await widget.deleteSession(session);
      if (!mounted) return;
      setState(() {
        _busySessionId = null;
        _sessions = widget.loadSessions();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.historySessionDeleted)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busySessionId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.historySessionDeleteFailed(error.toString())),
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
    final isClosed = session.status == 'closed';
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
        '${isActive ? context.l10n.sessionActive : isClosed ? context.l10n.sessionClosed : session.status}',
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isCurrent
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(label: Text(context.l10n.historySessionCurrent)),
                    if (isActive && widget.canCloseCurrentSession)
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
                    if (isClosed)
                      IconButton(
                        key: Key(
                          'reopen-history-session-${session.sessionId}',
                        ),
                        tooltip: context.l10n.historySessionReopenAction,
                        onPressed: _busySessionId == null
                            ? () => _reopen(session)
                            : null,
                        icon: Icon(
                          Icons.play_circle_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                )
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
                    if (isClosed)
                      IconButton(
                        key: Key(
                          'reopen-history-session-${session.sessionId}',
                        ),
                        tooltip: context.l10n.historySessionReopenAction,
                        onPressed: _busySessionId == null
                            ? () => _reopen(session)
                            : null,
                        icon: Icon(
                          Icons.play_circle_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (isClosed)
                      IconButton(
                        key: Key(
                          'delete-history-session-${session.sessionId}',
                        ),
                        tooltip: context.l10n.historySessionDeleteAction,
                        onPressed: _busySessionId == null
                            ? () => _delete(session)
                            : null,
                        icon: Icon(
                          Icons.delete_forever,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _DeleteSessionConfirmationDialog extends StatefulWidget {
  const _DeleteSessionConfirmationDialog({required this.sessionTitle});

  final String sessionTitle;

  @override
  State<_DeleteSessionConfirmationDialog> createState() =>
      _DeleteSessionConfirmationDialogState();
}

class _DeleteSessionConfirmationDialogState
    extends State<_DeleteSessionConfirmationDialog> {
  final _nameController = TextEditingController();
  bool _nameMatches = false;
  bool _nameChanged = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('delete-history-session-dialog'),
        title: Text(context.l10n.historySessionDeleteTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.historySessionDeleteWarning(widget.sessionTitle),
              ),
              const SizedBox(height: 12),
              SelectableText(
                context.l10n
                    .historySessionDeleteExpectedName(widget.sessionTitle),
                key: const Key('delete-history-session-expected-name'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('delete-history-session-name'),
                controller: _nameController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.l10n.historySessionDeleteNameLabel,
                  border: const OutlineInputBorder(),
                  errorText: _nameChanged && !_nameMatches
                      ? context.l10n.historySessionDeleteNameMismatch
                      : null,
                ),
                onChanged: (value) {
                  final matches = value.trim() == widget.sessionTitle;
                  if (matches != _nameMatches || !_nameChanged) {
                    setState(() {
                      _nameChanged = true;
                      _nameMatches = matches;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-history-session'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _nameMatches ? () => Navigator.pop(context, true) : null,
            child: Text(context.l10n.historySessionDeleteAction),
          ),
        ],
      );
}
