import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/utils/log_time.dart';

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
    final previousOrdinal = data.previous == null
        ? null
        : data.totalRecords > 0
            ? data.totalRecords
            : data.currentOrdinal > 1
                ? data.currentOrdinal - 1
                : null;
    final previousTitle = previousOrdinal == null
        ? context.l10n.previousSavedRecord
        : context.l10n.recordOrdinal(previousOrdinal);
    return _ControllerScaledViewport(
      scale: _preferences.scale,
      child: Scaffold(
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
                    final viewSize = MediaQuery.sizeOf(context);
                    final portrait = viewSize.height > viewSize.width;
                    final horizontal = !portrait && constraints.maxWidth >= 720;
                    final padding =
                        EdgeInsets.all(constraints.maxWidth < 720 ? 8 : 16);

                    if (horizontal) {
                      return Padding(
                        key: const Key('controller-landscape-layout'),
                        padding: padding,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _RecordPanel(
                                key: const Key('controller-current-panel'),
                                title: context.l10n
                                    .currentOrdinal(data.currentOrdinal),
                                icon: Icons.radio,
                                record: data.current,
                                fields: _preferences.fieldsFor(previous: false),
                                accent: theme.colorScheme.primary,
                                locks: data.locks,
                                prominent: true,
                                solidHeader: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _RecordPanel(
                                key: const Key('controller-previous-panel'),
                                title: previousTitle,
                                icon: Icons.history,
                                record: data.previous,
                                fields: _preferences.fieldsFor(previous: true),
                                accent: theme.colorScheme.tertiary,
                                locks: const [],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // 竖屏让整个记录区统一滚动，卡片按内容自然展开。这样手机和
                    // 平板不必把两张卡片强塞进有限高度，也不会出现两个很小的
                    // 嵌套滚动区。窄横屏也复用这个更稳妥的紧凑布局。
                    return SingleChildScrollView(
                      key: Key(
                        portrait
                            ? 'controller-portrait-layout'
                            : 'controller-compact-layout',
                      ),
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RecordPanel(
                            key: const Key('controller-current-panel'),
                            title: context.l10n
                                .currentOrdinal(data.currentOrdinal),
                            icon: Icons.radio,
                            record: data.current,
                            fields: _preferences.fieldsFor(previous: false),
                            accent: theme.colorScheme.primary,
                            locks: data.locks,
                            prominent: true,
                            solidHeader: true,
                            expandBody: false,
                          ),
                          const SizedBox(height: 12),
                          _RecordPanel(
                            key: const Key('controller-previous-panel'),
                            title: previousTitle,
                            icon: Icons.history,
                            record: data.previous,
                            fields: _preferences.fieldsFor(previous: true),
                            accent: theme.colorScheme.tertiary,
                            locks: const [],
                            expandBody: false,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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
                    const SizedBox(height: 20),
                    _ControllerScaleControl(
                      scale: pending.scale,
                      onChanged: (scale) =>
                          update(pending.copyWith(scale: scale)),
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

/// Applies browser-style zoom to a bounded logical viewport. The child lays
/// itself out at `physicalSize / scale` and is then painted back into the real
/// viewport, so responsive breakpoints and hit testing follow the visible UI.
class _ControllerScaledViewport extends StatelessWidget {
  const _ControllerScaledViewport({
    required this.scale,
    required this.child,
  });

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final normalized = ControllerDisplayPreferences.normalizeScale(scale);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        final logicalSize = Size(
          constraints.maxWidth / normalized,
          constraints.maxHeight / normalized,
        );
        final mediaQuery = MediaQuery.of(context);
        final logicalMediaQuery = mediaQuery.copyWith(
          size: logicalSize,
          padding: _scaleInsets(mediaQuery.padding, normalized),
          viewPadding: _scaleInsets(mediaQuery.viewPadding, normalized),
          viewInsets: _scaleInsets(mediaQuery.viewInsets, normalized),
          systemGestureInsets:
              _scaleInsets(mediaQuery.systemGestureInsets, normalized),
        );
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.scale(
              key: const Key('controller-display-scale-transform'),
              scale: normalized,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: logicalSize,
                child: MediaQuery(
                  data: logicalMediaQuery,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

EdgeInsets _scaleInsets(EdgeInsets value, double scale) => EdgeInsets.fromLTRB(
      value.left / scale,
      value.top / scale,
      value.right / scale,
      value.bottom / scale,
    );

class _ControllerScaleControl extends StatelessWidget {
  const _ControllerScaleControl({
    required this.scale,
    required this.onChanged,
  });

  final double scale;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = (scale * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.controllerDisplayScale,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '$percent%',
              key: const Key('controller-scale-value'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        Slider(
          key: const Key('controller-scale-slider'),
          value: scale,
          min: ControllerDisplayPreferences.minScale,
          max: ControllerDisplayPreferences.maxScale,
          divisions: ControllerDisplayPreferences.scaleDivisions,
          label: '$percent%',
          onChanged: onChanged,
        ),
        Text(
          context.l10n.controllerDisplayScaleHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
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
    final title = Text(
      data.sessionTitle.isEmpty
          ? context.l10n.controllerScreenFallbackTitle
          : data.sessionTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    final summary = Text(
      '${context.l10n.savedPositionCount(data.totalRecords)} · $updatedAt'
      '${data.lastUpdatedBy == null ? '' : ' · ${context.l10n.editorEditing(data.lastUpdatedBy!)}'}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );

    Widget statusChip() => _StatusChip(
          label: controllerConnectionLabel(
            context.l10n,
            data.connectionState,
          ),
          icon: connected ? Icons.cloud_done : Icons.cloud_off,
          color: connected ? Colors.green : theme.colorScheme.error,
        );

    Widget configureButton() => IconButton.filledTonal(
          key: const Key('configure-controller-display'),
          tooltip: context.l10n.configureControllerDisplay(
            controllerDetailLabel(context.l10n, detail),
          ),
          onPressed: onConfigure,
          icon: const Icon(Icons.tune),
        );

    Widget closeButton() => IconButton(
          tooltip: context.l10n.exitControllerScreen,
          onPressed: onClose,
          icon: const Icon(Icons.close_fullscreen),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                Icon(
                  Icons.podcasts,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 2), summary],
                  ),
                ),
                statusChip(),
                const SizedBox(width: 8),
                configureButton(),
                if (showCloseButton) ...[
                  const SizedBox(width: 4),
                  closeButton(),
                ],
              ],
            );
          }

          return Column(
            key: const Key('controller-compact-header'),
            children: [
              Row(
                children: [
                  Icon(
                    Icons.podcasts,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: title),
                  configureButton(),
                  if (showCloseButton) closeButton(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 8),
                  statusChip(),
                ],
              ),
            ],
          );
        },
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
    this.solidHeader = false,
    this.expandBody = true,
  });

  final String title;
  final IconData icon;
  final ControllerRecordDisplay? record;
  final Set<ControllerDisplayField> fields;
  final Color accent;
  final List<ControllerFieldLock> locks;
  final bool prominent;
  final bool solidHeader;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = record;
    final headerForeground = solidHeader ? theme.colorScheme.onPrimary : accent;
    final recordContent = value == null
        ? SizedBox(
            height: 120,
            child: Center(
              child: Text(
                context.l10n.noPreviousRecord,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        : Padding(
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
          );
    final body = value != null && expandBody
        ? SingleChildScrollView(child: recordContent)
        : recordContent;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: Key(
              prominent
                  ? 'controller-current-panel-header'
                  : 'controller-previous-panel-header',
            ),
            color: solidHeader ? accent : accent.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: headerForeground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: headerForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expandBody) Expanded(child: body) else body,
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
    // 旧缓存、桌面子窗口初始化参数和手工构造的 DTO 都可能仍携带
    // RFC 3339/ISO 原值。在最终渲染边界再格式化一次，且不回写模型。
    final displayValue = field == ControllerDisplayField.time
        ? formatLogTimeForDisplay(value)
        : value;
    final visibleValue = displayValue.trim().isEmpty ? '—' : displayValue;
    final valueText = Text(
      visibleValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
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
          if (field == ControllerDisplayField.remarks)
            Tooltip(message: visibleValue, child: valueText)
          else
            valueText,
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
