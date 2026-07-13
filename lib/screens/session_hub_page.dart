import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/collaboration_screen.dart';
import 'package:openlogtool/screens/controller_display_screen.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/widgets/session_title_editor.dart';
import 'package:provider/provider.dart';

/// “会话”区的统一入口。详细成员、邀请和冲突管理继续复用协作页面。
class SessionHubPage extends StatelessWidget {
  const SessionHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().currentSession;
    final logs = context.watch<LogProvider>();
    final collaboration = context.watch<CollaborationProvider>();
    final settings = context.watch<SettingsProvider>();
    final renameAvailability = session == null
        ? null
        : sessionRenameAvailability(
            sessionStatus: session.status,
            collaborationState: collaboration.state,
            hasCollaborationBinding: collaboration.binding != null,
            isCollaborationOwner: collaboration.isOwner,
            isBusy: collaboration.isBusy,
            hasOpenSessionConflict: collaboration.hasOpenSessionConflict,
          );
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final displayData = session == null
        ? null
        : _displayData(session.title, logs, collaboration);
    final appearance = ControllerWindowAppearance(
      themeColor: settings.themeColor,
      isDarkMode: settings.isDarkMode,
      fontFamily: settings.fontFamily,
    );
    if (displayData != null && supportsControllerDesktopWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ControllerWindowService.updateOpenWindows(
          data: displayData,
          preferences: settings.controllerDisplayPreferences,
          appearance: appearance,
        ).catchError((Object error) {
          debugPrint('[ControllerWindow] update failed: $error');
        });
      });
    }

    return ListView(
      key: const PageStorageKey('session-hub'),
      padding: EdgeInsets.all(isCompact ? 12 : 20),
      children: [
        Text(
          context.l10n.sessionsTitle,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.sessionsSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: session == null
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_busy),
                    title: Text(context.l10n.noCurrentSession),
                    subtitle: Text(context.l10n.noCurrentSessionHint),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            session.status == 'active'
                                ? Icons.radio_button_checked
                                : Icons.stop_circle_outlined,
                            color: session.status == 'active'
                                ? Colors.green
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        session.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Tooltip(
                                      message: sessionRenameAvailabilityLabel(
                                        context.l10n,
                                        renameAvailability!,
                                      ),
                                      child: IconButton(
                                        key: const Key('rename-session'),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: renameAvailability ==
                                                SessionRenameAvailability
                                                    .allowed
                                            ? () => _renameSession(
                                                  context,
                                                  session.title,
                                                  collaboration,
                                                )
                                            : null,
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${session.status == 'active' ? context.l10n.sessionActive : context.l10n.sessionClosed} · '
                                  '${context.l10n.savedPositions(logs.logCount)}',
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            avatar: Icon(
                              collaboration.binding == null
                                  ? Icons.person
                                  : Icons.groups,
                              size: 16,
                            ),
                            label: Text(
                              collaboration.binding == null
                                  ? context.l10n.localSession
                                  : context.l10n.collaborationState(
                                      collaborationStateLabel(
                                        context.l10n,
                                        collaboration.state.name,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        session.sessionId,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('open-collaboration-management'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const CollaborationScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.group_outlined),
                            label: Text(context.l10n.manageCollaboration),
                          ),
                          if (settings.controllerDeviceModeEnabled)
                            OutlinedButton.icon(
                              key: const Key('enter-controller-device-mode'),
                              onPressed: () => _openInAppController(context),
                              icon: const Icon(Icons.fullscreen),
                              label: Text(context.l10n.enterControllerScreen),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        if (session != null && supportsControllerDesktopWindows) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.localControllerDisplay,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(context.l10n.localControllerDisplayHint),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('open-controller-floating-window'),
                        onPressed: () => _openDesktopWindow(
                          context,
                          ControllerWindowMode.floating,
                          displayData!,
                          settings,
                          appearance,
                        ),
                        icon: const Icon(Icons.picture_in_picture_alt),
                        label: Text(context.l10n.openFloatingWindow),
                      ),
                      OutlinedButton.icon(
                        key: const Key('open-controller-second-window'),
                        onPressed: () => _openDesktopWindow(
                          context,
                          ControllerWindowMode.secondDisplay,
                          displayData!,
                          settings,
                          appearance,
                        ),
                        icon: const Icon(Icons.monitor),
                        label: Text(context.l10n.openSecondDisplayWindow),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(context.l10n.historySessions),
            subtitle: Text(context.l10n.historySessionsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: null,
          ),
        ),
      ],
    );
  }

  static ControllerDisplayDto _displayData(
    String sessionTitle,
    LogProvider logs,
    CollaborationProvider collaboration,
  ) {
    final snapshot = collaboration.liveDraftSnapshot;
    final draftFields = collaboration.liveDraftFields;
    final previous = logs.logs.isEmpty ? null : logs.logs.last;
    final connectionState = collaboration.binding == null
        ? ControllerConnectionState.connected
        : collaboration.state == CollaborationState.failed ||
                collaboration.state == CollaborationState.revoked ||
                collaboration.transportPhase ==
                    CollaborationTransportPhase.authRequired ||
                collaboration.transportPhase ==
                    CollaborationTransportPhase.incompatible ||
                collaboration.transportPhase ==
                    CollaborationTransportPhase.stopped
            ? ControllerConnectionState.offline
            : collaboration.transportPhase == CollaborationTransportPhase.online
                ? ControllerConnectionState.connected
                : ControllerConnectionState.reconnecting;
    if (snapshot != null) {
      final snapshotJson = Map<String, Object?>.from(snapshot.toJson());
      if (draftFields != null) {
        final draft = Map<String, Object?>.from(snapshotJson['draft']! as Map);
        draft['fields'] = draftFields.toJson();
        snapshotJson['draft'] = draft;
      }
      return ControllerDisplayDto.fromLiveDraftJson(
        snapshotJson,
        sessionTitle: sessionTitle,
        connectionState: connectionState,
      );
    }
    return ControllerDisplayDto(
      sessionTitle: sessionTitle,
      currentOrdinal: logs.logCount + 1,
      totalRecords: logs.logCount,
      current: ControllerRecordDisplay(
        controller: previous?.controller ?? '',
        rstSent: '59',
        rstRcvd: '59',
      ),
      previous:
          previous == null ? null : ControllerRecordDisplay.fromLog(previous),
      connectionState: connectionState,
      lastUpdatedAt:
          previous == null ? null : DateTime.tryParse(previous.updatedAt),
    );
  }

  static Future<void> _openInAppController(BuildContext context) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const _LiveControllerDisplayRoute(),
        ),
      );

  static Future<void> _renameSession(
    BuildContext context,
    String currentTitle,
    CollaborationProvider collaboration,
  ) async {
    final collaborationSession = collaboration.binding != null;
    final title = await showSessionRenameDialog(
      context,
      currentTitle: currentTitle,
      collaborationSession: collaborationSession,
    );
    if (title == null || !context.mounted) return;

    try {
      if (collaborationSession) {
        await collaboration.renameCurrentSession(title);
      } else {
        await context.read<SessionProvider>().renameCurrentSession(title);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            collaborationSession
                ? context.l10n.renameCollaborationSessionSaved
                : context.l10n.renameSessionSaved,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.renameSessionFailed(error.toString())),
        ),
      );
    }
  }

  static Future<void> _openDesktopWindow(
    BuildContext context,
    ControllerWindowMode mode,
    ControllerDisplayDto data,
    SettingsProvider settings,
    ControllerWindowAppearance appearance,
  ) async {
    try {
      await ControllerWindowService.open(
        mode: mode,
        data: data,
        preferences: settings.controllerDisplayPreferences,
        appearance: appearance,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.controllerWindowOpenFailed(error.toString()),
          ),
        ),
      );
    }
  }
}

class _LiveControllerDisplayRoute extends StatelessWidget {
  const _LiveControllerDisplayRoute();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().currentSession;
    final logs = context.watch<LogProvider>();
    final collaboration = context.watch<CollaborationProvider>();
    final settings = context.watch<SettingsProvider>();
    return ControllerDisplayScreen(
      data: SessionHubPage._displayData(
        session?.title ?? context.l10n.controllerScreenFallbackTitle,
        logs,
        collaboration,
      ),
      preferences: settings.controllerDisplayPreferences,
      onPreferencesChanged: settings.setControllerDisplayPreferences,
    );
  }
}
