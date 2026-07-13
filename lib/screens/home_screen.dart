import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/session_hub_page.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:openlogtool/widgets/log_table.dart';
import 'package:openlogtool/widgets/dictionary_manager.dart';
import 'package:openlogtool/widgets/export_panel.dart';
import 'package:openlogtool/widgets/settings_panel.dart';
import 'package:openlogtool/widgets/primary_navigation_rail.dart';
import 'package:openlogtool/widgets/session_history_dialog.dart';
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
      var recordName = '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.newRecordName),
          content: TextField(
            autofocus: true,
            onChanged: (value) => recordName = value,
            decoration: InputDecoration(
              hintText: ctx.l10n.newRecordNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            FilledButton(
              child: Text(ctx.l10n.startNewRecord),
              onPressed: () async {
                final name = recordName.trim();
                await sp.startNewSession(title: name.isEmpty ? null : name);
                await lp.reloadForSession(sp.currentSessionId);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
      return;
    }
    lp.reloadForSession(sp.currentSessionId);
  }

  void _onItemTapped(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedIndex = index);
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
      const ImportExportPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_selectedIndex].label(context.l10n)),
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
              const VerticalDivider(width: 1),
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
  Widget build(BuildContext context) => const Column(
        children: [
          _WorkbenchStatusBar(),
          Expanded(child: AddRecordPage()),
        ],
      );
}

class _WorkbenchStatusBar extends StatelessWidget {
  const _WorkbenchStatusBar();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().currentSession;
    final collaboration = context.watch<CollaborationProvider>();
    final theme = Theme.of(context);
    return Container(
      key: const Key('workbench-status-bar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusLabel(
            icon: Icons.event_note,
            text: session?.title ?? context.l10n.workbenchNoSession,
          ),
          _StatusLabel(
            icon: collaboration.binding == null
                ? Icons.person_outline
                : Icons.groups_outlined,
            text: collaboration.binding == null
                ? context.l10n.workbenchLocalRecording
                : context.l10n.collaborationState(
                    collaborationStateLabel(
                      context.l10n,
                      collaboration.state.name,
                    ),
                  ),
          ),
          if (collaboration.binding != null) ...[
            _StatusLabel(
              icon: Icons.sync,
              text: context.l10n.pendingSyncCount(collaboration.pendingCount),
            ),
            _StatusLabel(
              icon: Icons.warning_amber,
              text: context.l10n.conflictCount(collaboration.conflictCount),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppBarSyncStatus extends StatelessWidget {
  const _AppBarSyncStatus();

  @override
  Widget build(BuildContext context) {
    final collaboration = context.watch<CollaborationProvider>();
    final local = collaboration.binding == null;
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
      message: local
          ? context.l10n.localSessionTooltip
          : context.l10n.collaborationStatusTooltip(
              statusLabel,
              collaboration.pendingCount,
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          local
              ? Icons.cloud_off_outlined
              : online
                  ? Icons.cloud_done_outlined
                  : reconnecting
                      ? Icons.sync
                      : Icons.cloud_off,
          color: local
              ? null
              : online
                  ? Colors.green
                  : reconnecting
                      ? Colors.orange
                      : Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 5),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class AddRecordPage extends StatelessWidget {
  const AddRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final currentSession = context.watch<SessionProvider>().currentSession;
    final sessionClosed =
        currentSession != null && currentSession.status != 'active';
    final readOnly = logProvider.currentSessionReadOnly || sessionClosed;
    final conflictedLogIds =
        context.watch<CollaborationProvider>().conflictedLogIds;
    final content = _buildStackedLayout(
      context,
      logProvider,
      conflictedLogIds,
      readOnly,
      currentSession?.sessionId,
    );
    if (!readOnly) return content;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sessionClosed
                      ? context.l10n.historySessionReadOnly
                      : context.l10n.sharedDraftReadOnly,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildStackedLayout(
    BuildContext context,
    LogProvider logProvider,
    Set<String> conflictedLogIds,
    bool readOnly,
    String? currentSessionId,
  ) {
    final stackedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.currentRecord,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _currentOrdinalBadge(context, logProvider.logCount),
                  ],
                ),
                const SizedBox(height: 12),
                LogForm(
                  key: ValueKey('log-form-${currentSessionId ?? 'none'}'),
                  readOnly: readOnly,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogHeader(context, readOnly),
                const SizedBox(height: 12),
                const Text(
                  '已有记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                LogTable(
                  readOnly: readOnly,
                  conflictedLogIds: conflictedLogIds,
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final limitWidth = context.select<SettingsProvider, bool>(
      (settings) => settings.limitWorkbenchWidth,
    );
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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

  Widget _buildLogHeader(
    BuildContext context,
    bool readOnly,
  ) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Consumer<LogProvider>(
          builder: (_, lp, __) => Chip(label: Text('${lp.logCount} 条记录')),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Consumer<LogProvider>(
              builder: (_, lp, __) => FilledButton(
                onPressed: !readOnly && lp.canUndo
                    ? () => _showUndoConfirmation(context)
                    : null,
                child: const Text('撤销'),
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('start-new-record'),
              onPressed: () => _showNewSessionNameDialog(context),
              icon: const Icon(Icons.note_add_outlined),
              label: Text(context.l10n.startNewRecord),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: context.l10n.historySessions,
              onPressed: () => showSessionHistoryDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showNewSessionNameDialog(BuildContext context) async {
    var recordName = '';
    final sessionProvider =
        Provider.of<SessionProvider>(context, listen: false);
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.newRecordName),
        content: TextField(
          autofocus: true,
          onChanged: (value) => recordName = value,
          decoration: InputDecoration(
            hintText: ctx.l10n.newRecordNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            child: Text(ctx.l10n.cancel),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: Text(ctx.l10n.startNewRecord),
            onPressed: () async {
              try {
                final name = recordName.trim();
                await sessionProvider.startNewSession(
                    title: name.isEmpty ? null : name);
                await logProvider
                    .reloadForSession(sessionProvider.currentSessionId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    SnackBar(
                      content: Text(
                        context.l10n.newRecordStarted(
                          name.isEmpty ? context.l10n.automaticName : name,
                        ),
                      ),
                    ),
                  );
                }
              } catch (e, st) {
                debugPrint('[SessionDialog] ERROR: $e\n$st');
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    SnackBar(
                      content: Text(context.l10n.createNewRecordFailed('$e')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showUndoConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认撤销'),
        content: const Text('您确定要撤销上一条记录吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('确认撤销'),
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).undoLastLog();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class ImportExportPage extends StatelessWidget {
  const ImportExportPage({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: ExportPanel(),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: DictionaryManager(),
              ),
            ),
          ],
        ),
      );
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
