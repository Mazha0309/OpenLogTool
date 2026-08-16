import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/services/app_logger.dart';
import 'package:openlogtool/theme/app_theme.dart';

/// Persistent diagnostic log browser used by the settings support section.
class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Set<AppLogLevel> _levels = AppLogLevel.values.toSet();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxHeight = math.min(
      math.max(mediaSize.height - 32.0, 280.0),
      720.0,
    );

    return Dialog(
      key: const Key('log-viewer-dialog'),
      insetPadding: const EdgeInsets.all(AppSpace.md),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820, maxHeight: maxHeight),
        child: AnimatedBuilder(
          animation: AppLogger.instance,
          builder: (context, _) {
            final allEntries = AppLogger.instance.snapshotEntries();
            final filtered = allEntries.reversed.where(_matches).toList();
            return Column(
              children: [
                _buildHeader(context, allEntries.length),
                const Divider(height: 1),
                _buildFilters(context),
                const Divider(height: 1),
                Expanded(
                  child: _buildLogList(context, allEntries, filtered),
                ),
                const Divider(height: 1),
                _buildActions(context, filtered),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.logsTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.logsCount(count),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.logsClose,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );

  Widget _buildFilters(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('log-viewer-search'),
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.l10n.logsSearchHint,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.logsClear,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppSpace.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    key: const Key('log-level-all'),
                    label: Text(context.l10n.logsLevelAll),
                    selected: _levels.length == AppLogLevel.values.length,
                    onSelected: (selected) {
                      setState(() {
                        _levels
                          ..clear()
                          ..addAll(selected ? AppLogLevel.values : const []);
                      });
                    },
                  ),
                  const SizedBox(width: AppSpace.xs),
                  for (final level in AppLogLevel.values) ...[
                    FilterChip(
                      key: Key('log-level-${level.name}'),
                      avatar: Icon(
                        _levelIcon(level),
                        size: 16,
                        color: _levelColor(context, level),
                      ),
                      label: Text(_levelLabel(context, level)),
                      selected: _levels.contains(level),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _levels.add(level);
                          } else {
                            _levels.remove(level);
                          }
                        });
                      },
                    ),
                    const SizedBox(width: AppSpace.xs),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildLogList(
    BuildContext context,
    List<AppLogEntry> allEntries,
    List<AppLogEntry> filtered,
  ) {
    if (allEntries.isEmpty) {
      return Center(child: Text(context.l10n.logsEmpty));
    }
    if (filtered.isEmpty) {
      return Center(child: Text(context.l10n.logsNoFilterResults));
    }
    return ListView.separated(
      key: const Key('log-viewer-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (context, index) {
        final entry = filtered[index];
        return _LogEntryTile(
          key: ValueKey(
            '${entry.timestamp.microsecondsSinceEpoch}-${entry.source}-$index',
          ),
          entry: entry,
          color: _levelColor(context, entry.level),
          icon: _levelIcon(entry.level),
          levelLabel: _levelLabel(context, entry.level),
        );
      },
    );
  }

  Widget _buildActions(
    BuildContext context,
    List<AppLogEntry> filtered,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasEntries = AppLogger.instance.snapshotEntries().isNotEmpty;
            if (constraints.maxWidth < 480) {
              return Row(
                children: [
                  IconButton(
                    key: const Key('log-viewer-clear'),
                    tooltip: context.l10n.logsClear,
                    onPressed: hasEntries ? () => _confirmClear(context) : null,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('log-viewer-copy'),
                    tooltip: context.l10n.logsCopy,
                    onPressed: filtered.isEmpty
                        ? null
                        : () => _copyLogs(context, filtered),
                    icon: const Icon(Icons.copy_outlined, size: 20),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  IconButton.filled(
                    key: const Key('log-viewer-close'),
                    tooltip: context.l10n.logsClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              );
            }
            final clear = TextButton.icon(
              key: const Key('log-viewer-clear'),
              onPressed: hasEntries ? () => _confirmClear(context) : null,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(context.l10n.logsClear),
            );
            final copy = TextButton.icon(
              key: const Key('log-viewer-copy'),
              onPressed:
                  filtered.isEmpty ? null : () => _copyLogs(context, filtered),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(context.l10n.logsCopy),
            );
            final close = FilledButton(
              key: const Key('log-viewer-close'),
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.logsClose),
            );
            return Row(
              children: [
                clear,
                const Spacer(),
                copy,
                const SizedBox(width: AppSpace.xs),
                close,
              ],
            );
          },
        ),
      );

  bool _matches(AppLogEntry entry) {
    if (!_levels.contains(entry.level)) return false;
    final query = _query.toLowerCase();
    return query.isEmpty || entry.searchableText.contains(query);
  }

  Future<void> _copyLogs(
    BuildContext context,
    List<AppLogEntry> entries,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: entries.reversed
            .map((entry) => entry.toDisplayString())
            .join('\n\n'),
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.logsCopied)),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.logsClearTitle),
        content: Text(dialogContext.l10n.logsClearConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.logsClear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clear();
    if (!context.mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.logsCleared)),
    );
  }

  String _levelLabel(BuildContext context, AppLogLevel level) =>
      switch (level) {
        AppLogLevel.debug => context.l10n.logsLevelDebug,
        AppLogLevel.info => context.l10n.logsLevelInfo,
        AppLogLevel.warning => context.l10n.logsLevelWarning,
        AppLogLevel.error => context.l10n.logsLevelError,
      };

  IconData _levelIcon(AppLogLevel level) => switch (level) {
        AppLogLevel.debug => Icons.bug_report_outlined,
        AppLogLevel.info => Icons.info_outline,
        AppLogLevel.warning => Icons.warning_amber_rounded,
        AppLogLevel.error => Icons.error_outline,
      };

  Color _levelColor(BuildContext context, AppLogLevel level) => switch (level) {
        AppLogLevel.debug => Theme.of(context).colorScheme.outline,
        AppLogLevel.info => Theme.of(context).colorScheme.primary,
        AppLogLevel.warning => Colors.orange.shade700,
        AppLogLevel.error => Theme.of(context).colorScheme.error,
      };
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({
    super.key,
    required this.entry,
    required this.color,
    required this.icon,
    required this.levelLabel,
  });

  final AppLogEntry entry;
  final Color color;
  final IconData icon;
  final String levelLabel;

  @override
  Widget build(BuildContext context) {
    final local = entry.timestamp.toLocal();
    final timestamp = '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
    final details = entry.toDisplayString();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 21),
        title: Text(
          entry.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(
          '$timestamp · $levelLabel · ${entry.source}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SelectableText(
              details,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
