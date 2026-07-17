import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/data_workspace_page.dart';
import 'package:openlogtool/screens/session_hub_page.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:openlogtool/widgets/log_table.dart';
import 'package:openlogtool/widgets/settings_panel.dart';
import 'package:openlogtool/widgets/primary_navigation_rail.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _destinations = <_AppDestination>[
    _AppDestination(_AppSection.workbench, Icons.radio_outlined, Icons.radio),
    _AppDestination(_AppSection.sessions, Icons.groups_outlined, Icons.groups),
    _AppDestination(_AppSection.data, Icons.storage_outlined, Icons.storage),
    _AppDestination(
        _AppSection.settings, Icons.settings_outlined, Icons.settings),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSession());
  }

  @override
  void dispose() {
    ControllerWindowService.closeAll().catchError((Object error) {
      debugPrint('[ControllerWindow] close failed: $error');
    });
    super.dispose();
  }

  Future<void> _initSession() async {
    final sp = context.read<SessionProvider>();
    final lp = context.read<LogProvider>();
    await sp.ready;
    if (!mounted) return;
    if (sp.currentSessionId == null) {
      setState(() => _selectedIndex = 1);
      return;
    }
    await lp.reloadForSession(sp.currentSessionId);
  }

  void _onItemTapped(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final destination =
        index == 0 && context.read<SessionProvider>().currentSessionId == null
            ? 1
            : index;
    setState(() => _selectedIndex = destination);
  }

  @override
  Widget build(BuildContext context) {
    final primarySidebarExpanded = context.select<SettingsProvider, bool>(
      (settings) => settings.primarySidebarExpanded,
    );
    final pages = <Widget>[
      const _WorkbenchPage(),
      SessionHubPage(
        onSessionOpened: () {
          if (mounted) setState(() => _selectedIndex = 0);
        },
      ),
      const DataWorkspacePage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _destinations[_selectedIndex].selectedIcon,
              size: 21,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Text(_destinations[_selectedIndex].label(context.l10n)),
          ],
        ),
        centerTitle: false,
        actions: const [_AppBarSyncStatus(), SizedBox(width: 8)],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = IndexedStack(
            index: _selectedIndex,
            children: pages,
          );
          if (constraints.maxWidth < 720) return content;
          final isDesktop = constraints.maxWidth >= 1200;
          return Row(
            children: [
              PrimaryNavigationRail(
                isDesktop: isDesktop,
                expanded: primarySidebarExpanded,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                onExpandedChanged:
                    context.read<SettingsProvider>().setPrimarySidebarExpanded,
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label(context.l10n)),
                    ),
                ],
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 720
          ? NavigationBar(
              key: const Key('mobile-navigation'),
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label(context.l10n),
                  ),
              ],
            )
          : null,
    );
  }
}

enum _AppSection { workbench, sessions, data, settings }

class _AppDestination {
  const _AppDestination(this.section, this.icon, this.selectedIcon);

  final _AppSection section;
  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l10n) => switch (section) {
        _AppSection.workbench => l10n.navWorkbench,
        _AppSection.sessions => l10n.navSessions,
        _AppSection.data => l10n.navData,
        _AppSection.settings => l10n.navSettings,
      };
}

class _WorkbenchPage extends StatelessWidget {
  const _WorkbenchPage();

  @override
  Widget build(BuildContext context) => const AddRecordPage();
}

class _WorkbenchStatusBar extends StatelessWidget {
  const _WorkbenchStatusBar();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().currentSession;
    if (session == null) return const SizedBox.shrink();
    final collaboration = context.watch<CollaborationProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      key: const Key('workbench-status-bar'),
      width: double.infinity,
      child: Container(
        key: const Key('workbench-session-header'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final introduction = Row(
              key: const Key('workbench-session-summary'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.radio_outlined,
                    size: 18,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        session.status == 'active'
                            ? context.l10n.sessionActive
                            : context.l10n.sessionClosed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final statusWidgets = <Widget>[
              _StatusLabel(
                icon: collaboration.binding == null
                    ? Icons.person_outline
                    : Icons.groups_outlined,
                text: collaboration.binding == null
                    ? context.l10n.collaborationLocalOnly
                    : collaborationStateLabel(
                        context.l10n,
                        collaboration.state.name,
                      ),
              ),
              if (collaboration.binding != null) ...[
                _StatusLabel(
                  icon: Icons.sync,
                  text:
                      context.l10n.pendingSyncCount(collaboration.pendingCount),
                ),
                _StatusLabel(
                  icon: Icons.warning_amber,
                  text: context.l10n.conflictCount(collaboration.conflictCount),
                  danger: collaboration.conflictCount > 0,
                ),
              ],
            ];
            final statuses = Wrap(
              key: const Key('workbench-session-statuses'),
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: statusWidgets,
            );
            final stackStatuses =
                constraints.maxWidth < 640 && collaboration.binding != null;
            if (stackStatuses) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  introduction,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: statuses,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: introduction),
                const SizedBox(width: 12),
                statuses,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppBarSyncStatus extends StatelessWidget {
  const _AppBarSyncStatus();

  @override
  Widget build(BuildContext context) {
    final hasSession = context.select<SessionProvider, bool>(
      (sessions) => sessions.currentSession != null,
    );
    final collaboration = context.watch<CollaborationProvider>();
    final local = collaboration.binding == null;
    if (!hasSession || local) return const SizedBox.shrink();
    final online =
        collaboration.transportPhase == CollaborationTransportPhase.online;
    final reconnecting = collaboration.transportPhase ==
            CollaborationTransportPhase.connecting ||
        collaboration.transportPhase == CollaborationTransportPhase.backingOff;
    final statusLabel = collaboration.state == CollaborationState.ready
        ? online
            ? context.l10n.connectionConnected
            : reconnecting
                ? context.l10n.connectionReconnecting
                : context.l10n.connectionOffline
        : collaborationStateLabel(
            context.l10n,
            collaboration.state.name,
          );
    return Tooltip(
      message: context.l10n.collaborationStatusTooltip(
        statusLabel,
        collaboration.pendingCount,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          online
              ? Icons.cloud_done_outlined
              : reconnecting
                  ? Icons.sync
                  : Icons.cloud_off,
          color: online
              ? Colors.green
              : reconnecting
                  ? Colors.orange
                  : Theme.of(context).colorScheme.error,
          size: 20,
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({
    required this.icon,
    required this.text,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = danger ? colors.error : colors.onSurfaceVariant;
    final background = danger
        ? colors.errorContainer.withValues(alpha: 0.6)
        : colors.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchSectionCard extends StatelessWidget {
  const _WorkbenchSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Widget title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final heading = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: title),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final action = trailing;
                if (action == null) return heading;
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: action,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 16),
                    action,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class AddRecordPage extends StatelessWidget {
  const AddRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentSession = context.watch<SessionProvider>().currentSession;
    if (currentSession == null) return _buildNoSessionState(context);

    final logProvider = Provider.of<LogProvider>(context);
    final sessionClosed = currentSession.status != 'active';
    final readOnly = logProvider.currentSessionReadOnly || sessionClosed;
    final conflictedLogIds =
        context.watch<CollaborationProvider>().conflictedLogIds;
    final content = _buildStackedLayout(
      context,
      logProvider,
      conflictedLogIds,
      readOnly,
      currentSession.sessionId,
    );
    return content;
  }

  Widget _buildNoSessionState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.event_note_outlined,
                      size: 32,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.noCurrentSession,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.noCurrentSessionHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStackedLayout(
    BuildContext context,
    LogProvider logProvider,
    Set<String> conflictedLogIds,
    bool readOnly,
    String currentSessionId,
  ) {
    final stackedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _WorkbenchStatusBar(),
        if (readOnly) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('workbench-read-only-banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.watch<SessionProvider>().currentSession?.status !=
                            'active'
                        ? context.l10n.historySessionReadOnly
                        : context.l10n.sharedDraftReadOnly,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          key: const Key('current-record-section'),
          icon: Icons.edit_note_outlined,
          title: Text(
            context.l10n.currentRecord,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          trailing: _currentOrdinalBadge(context, logProvider.logCount),
          child: LogForm(
            key: ValueKey('log-form-$currentSessionId'),
            readOnly: readOnly,
          ),
        ),
        const SizedBox(height: 16),
        _WorkbenchSectionCard(
          key: const Key('saved-records-section'),
          icon: Icons.format_list_numbered_outlined,
          title: Consumer<LogProvider>(
            builder: (_, lp, __) => Row(
              children: [
                Flexible(
                  child: Text(
                    context.l10n.savedRecords,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.l10n.recordCount(lp.logCount),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          trailing: _buildLogActions(context, readOnly),
          child: LogTable(
            readOnly: readOnly,
            conflictedLogIds: conflictedLogIds,
          ),
        ),
      ],
    );
    final limitWidth = context.select<SettingsProvider, bool>(
      (settings) => settings.limitWorkbenchWidth,
    );
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: limitWidth
          ? Center(
              child: ConstrainedBox(
                key: const Key('workbench-width-limit'),
                constraints: const BoxConstraints(maxWidth: 1440),
                child: stackedContent,
              ),
            )
          : stackedContent,
    );
  }

  Widget _currentOrdinalBadge(BuildContext context, int savedCount) {
    final colors = Theme.of(context).colorScheme;
    final ordinal = context
            .watch<CollaborationProvider>()
            .liveDraftSnapshot
            ?.currentOrdinal ??
        savedCount + 1;
    return Container(
      key: const Key('current-ordinal-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l10n.currentOrdinal(ordinal),
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLogActions(
    BuildContext context,
    bool readOnly,
  ) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Consumer<LogProvider>(
          builder: (_, lp, __) => OutlinedButton.icon(
            onPressed: !readOnly && lp.canUndo
                ? () => _showUndoConfirmation(context)
                : null,
            icon: const Icon(Icons.restore),
            label: Text(context.l10n.restoreLastDeletedRecord),
          ),
        ),
      ],
    );
  }

  Future<void> _showUndoConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.restoreLastDeletedRecordTitle),
        content: Text(dialogContext.l10n.restoreLastDeletedRecordConfirmation),
        actions: [
          TextButton(
            child: Text(dialogContext.l10n.cancel),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          FilledButton(
            child: Text(dialogContext.l10n.restoreLastDeletedRecord),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<LogProvider>().undoLastLog();
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.recordRestored)),
      );
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed('$error'))),
      );
    }
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 8 : 24,
            vertical: isNarrow ? 12 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: const SettingsPanel(),
            ),
          ),
        );
      },
    );
  }
}
