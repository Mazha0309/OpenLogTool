import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';

/// 跨平台只读主控屏。安卓平板、独立电脑和桌面子窗口共用此页面。
class ControllerDisplayScreen extends StatefulWidget {
  const ControllerDisplayScreen({
    super.key,
    required this.data,
    this.preferences = const ControllerDisplayPreferences(),
    this.onPreferencesChanged,
    this.showCloseButton = true,
    this.onClose,
  });

  final ControllerDisplayDto data;
  final ControllerDisplayPreferences preferences;
  final ValueChanged<ControllerDisplayPreferences>? onPreferencesChanged;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  State<ControllerDisplayScreen> createState() =>
      _ControllerDisplayScreenState();
}

class _ControllerDisplayScreenState extends State<ControllerDisplayScreen> {
  late ControllerDisplayPreferences _preferences = widget.preferences;

  @override
  void didUpdateWidget(ControllerDisplayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _preferences = widget.preferences;
    }
  }

  void _setPreferences(ControllerDisplayPreferences value) {
    setState(() => _preferences = value);
    widget.onPreferencesChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _ControllerHeader(
              data: data,
              detail: _preferences.detail,
              showCloseButton: widget.showCloseButton,
              onConfigure: _showConfiguration,
              onClose: widget.onClose ?? () => Navigator.maybePop(context),
            ),
            if (data.isStale)
              MaterialBanner(
                key: const Key('controller-stale-banner'),
                backgroundColor: theme.colorScheme.errorContainer,
                leading: Icon(
                  Icons.cloud_off,
                  color: theme.colorScheme.onErrorContainer,
                ),
                content: Text(
                  context.l10n.staleControllerDataWarning,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                actions: const [SizedBox.shrink()],
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 1000;
                  final panels = [
                    Expanded(
                      flex: 3,
                      child: _RecordPanel(
                        key: const Key('controller-current-panel'),
                        title: context.l10n.currentOrdinal(data.currentOrdinal),
                        icon: Icons.radio,
                        record: data.current,
                        fields: _preferences.fieldsFor(previous: false),
                        accent: theme.colorScheme.primary,
                        locks: data.locks,
                        prominent: true,
                      ),
                    ),
                    SizedBox(
                      width: horizontal ? 16 : 0,
                      height: horizontal ? 0 : 12,
                    ),
                    Expanded(
                      flex: 2,
                      child: _RecordPanel(
                        key: const Key('controller-previous-panel'),
                        title: context.l10n.previousSavedRecord,
                        icon: Icons.history,
                        record: data.previous,
                        fields: _preferences.fieldsFor(previous: true),
                        accent: theme.colorScheme.tertiary,
                        locks: const [],
                      ),
                    ),
                  ];
                  return Padding(
                    padding:
                        EdgeInsets.all(constraints.maxWidth < 720 ? 8 : 16),
                    child: horizontal
                        ? Row(children: panels)
                        : Column(children: panels),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfiguration() async {
    var pending = _preferences;
    final result = await showDialog<ControllerDisplayPreferences>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(ControllerDisplayPreferences next) {
            setDialogState(() => pending = next);
          }

          return AlertDialog(
            title: Text(context.l10n.controllerDisplayConfiguration),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<ControllerDisplayDetail>(
                      key: const Key('controller-detail-picker'),
                      initialValue: pending.detail,
                      decoration: InputDecoration(
                        labelText: context.l10n.informationDetail,
                        border: const OutlineInputBorder(),
                      ),
                      items: ControllerDisplayDetail.values
                          .map(
                            (detail) => DropdownMenuItem(
                              value: detail,
                              child: Text(
                                controllerDetailLabel(context.l10n, detail),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (detail) {
                        if (detail != null) {
                          update(pending.copyWith(detail: detail));
                        }
                      },
                    ),
                    if (pending.detail == ControllerDisplayDetail.custom) ...[
                      const SizedBox(height: 20),
                      _FieldSelector(
                        title: context.l10n.currentFields,
                        selected: pending.currentFields,
                        onChanged: (fields) =>
                            update(pending.copyWith(currentFields: fields)),
                      ),
                      const SizedBox(height: 16),
                      _FieldSelector(
                        title: context.l10n.previousFields,
                        selected: pending.previousFields,
                        onChanged: (fields) =>
                            update(pending.copyWith(previousFields: fields)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: const Key('save-controller-display-settings'),
                onPressed: () => Navigator.pop(dialogContext, pending),
                child: Text(context.l10n.apply),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) _setPreferences(result);
  }
}

class _ControllerHeader extends StatelessWidget {
  const _ControllerHeader({
    required this.data,
    required this.detail,
    required this.showCloseButton,
    required this.onConfigure,
    required this.onClose,
  });

  final ControllerDisplayDto data;
  final ControllerDisplayDetail detail;
  final bool showCloseButton;
  final VoidCallback onConfigure;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected =
        data.connectionState == ControllerConnectionState.connected;
    final updatedAt = data.lastUpdatedAt == null
        ? context.l10n.notReceivedDraftUpdate
        : context.l10n.updatedAt(
            DateFormat('HH:mm:ss').format(data.lastUpdatedAt!.toLocal()),
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.podcasts, color: theme.colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.sessionTitle.isEmpty
                      ? context.l10n.controllerScreenFallbackTitle
                      : data.sessionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${context.l10n.savedPositionCount(data.totalRecords)} · $updatedAt'
                  '${data.lastUpdatedBy == null ? '' : ' · ${context.l10n.editorEditing(data.lastUpdatedBy!)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _StatusChip(
            label: controllerConnectionLabel(
              context.l10n,
              data.connectionState,
            ),
            icon: connected ? Icons.cloud_done : Icons.cloud_off,
            color: connected ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const Key('configure-controller-display'),
            tooltip: context.l10n.configureControllerDisplay(
              controllerDetailLabel(context.l10n, detail),
            ),
            onPressed: onConfigure,
            icon: const Icon(Icons.tune),
          ),
          if (showCloseButton) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: context.l10n.exitControllerScreen,
              onPressed: onClose,
              icon: const Icon(Icons.close_fullscreen),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: color.withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _RecordPanel extends StatelessWidget {
  const _RecordPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.record,
    required this.fields,
    required this.accent,
    required this.locks,
    this.prominent = false,
  });

  final String title;
  final IconData icon;
  final ControllerRecordDisplay? record;
  final Set<ControllerDisplayField> fields;
  final Color accent;
  final List<ControllerFieldLock> locks;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = record;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: accent.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: value == null
                ? Center(
                    child: Text(
                      context.l10n.noPreviousRecord,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (prominent &&
                            fields.contains(ControllerDisplayField.callsign))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              value.callsign.trim().isEmpty
                                  ? context.l10n.waitingForCallsign
                                  : value.callsign,
                              key: const Key('controller-prominent-callsign'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final tileWidth = constraints.maxWidth >= 760
                                ? (constraints.maxWidth - 24) / 3
                                : constraints.maxWidth >= 440
                                    ? (constraints.maxWidth - 12) / 2
                                    : constraints.maxWidth;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final field in fields)
                                  SizedBox(
                                    width: tileWidth,
                                    child: _FieldTile(
                                      field: field,
                                      value: value.valueFor(field),
                                      lock: _lockFor(field),
                                      accent: accent,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  ControllerFieldLock? _lockFor(ControllerDisplayField field) {
    for (final lock in locks) {
      if (lock.field == field.wireName) return lock;
    }
    return null;
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.field,
    required this.value,
    required this.lock,
    required this.accent,
  });

  final ControllerDisplayField field;
  final String value;
  final ControllerFieldLock? lock;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: Key('controller-field-${field.wireName}'),
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lock == null
              ? theme.colorScheme.outlineVariant
              : accent.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(
                controllerFieldLabel(context.l10n, field),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (lock != null) ...[
                const Spacer(),
                Icon(Icons.edit, size: 13, color: accent),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    lock!.holderName ?? context.l10n.beingEdited,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: accent),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            value.trim().isEmpty ? '—' : value,
            maxLines: field == ControllerDisplayField.remarks ? 3 : 1,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldSelector extends StatelessWidget {
  const _FieldSelector({
    required this.title,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final Set<ControllerDisplayField> selected;
  final ValueChanged<Set<ControllerDisplayField>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final field in ControllerDisplayField.values)
                FilterChip(
                  label: Text(controllerFieldLabel(context.l10n, field)),
                  selected: selected.contains(field),
                  onSelected: (enabled) {
                    final next = Set<ControllerDisplayField>.from(selected);
                    enabled ? next.add(field) : next.remove(field);
                    onChanged(next);
                  },
                ),
            ],
          ),
        ],
      );
}
