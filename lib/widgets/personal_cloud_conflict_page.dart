import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/utils/personal_cloud_merge.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';
import 'package:provider/provider.dart';

/// A durable, full-page decision surface for account personal-cloud conflicts.
///
/// Choices intentionally start empty: applying a merge requires an explicit
/// decision for every field or entity instead of silently preferring a side.
class PersonalCloudConflictPage extends StatefulWidget {
  const PersonalCloudConflictPage({
    super.key,
    required this.onOpenDatabase,
  });

  final VoidCallback onOpenDatabase;

  @override
  State<PersonalCloudConflictPage> createState() =>
      _PersonalCloudConflictPageState();
}

class _PersonalCloudConflictPageState extends State<PersonalCloudConflictPage> {
  final Map<String, PersonalCloudConflictChoice> _choices = {};
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<PersonalCloudProvider>();
    final conflicts = cloud.conflicts;
    final activeIds = conflicts.map((conflict) => conflict.conflictId).toSet();
    _choices.removeWhere((id, _) => !activeIds.contains(id));

    return AppPageFrame(
      scrollKey: const PageStorageKey('personal-cloud-conflict-page'),
      header: AppPageHeader(
        icon: Icons.rule_folder_outlined,
        title: context.l10n.personalCloudConflictPageTitle,
        description: context.l10n.personalCloudConflictPageHint,
        actions: conflicts.isEmpty
            ? const <Widget>[]
            : <Widget>[
                OutlinedButton.icon(
                  key: const Key('personal-cloud-select-all-local'),
                  onPressed: _isBusy(cloud)
                      ? null
                      : () => _selectAll(
                            conflicts,
                            PersonalCloudConflictChoice.local,
                          ),
                  icon: const Icon(Icons.laptop_outlined),
                  label: Text(
                    context.l10n.personalCloudConflictSelectAllLocal,
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('personal-cloud-select-all-remote'),
                  onPressed: _isBusy(cloud)
                      ? null
                      : () => _selectAll(
                            conflicts,
                            PersonalCloudConflictChoice.remote,
                          ),
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(
                    context.l10n.personalCloudConflictSelectAllRemote,
                  ),
                ),
              ],
      ),
      child: conflicts.isEmpty
          ? _EmptyConflictState(
              confirmationPending:
                  cloud.hasPendingMerge && cloud.pendingMergeNeedsConfirmation,
              onOpenDatabase: widget.onOpenDatabase,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNotice(
                  key: const Key('personal-cloud-conflict-progress'),
                  message: context.l10n.personalCloudConflictSelectionProgress(
                    _choices.length,
                    conflicts.length,
                  ),
                  icon: Icons.fact_check_outlined,
                  tone: _choices.length == conflicts.length
                      ? AppTone.success
                      : AppTone.warning,
                ),
                const SizedBox(height: AppSpace.md),
                for (var index = 0; index < conflicts.length; index++) ...[
                  _PersonalCloudConflictCard(
                    conflict: conflicts[index],
                    choice: _choices[conflicts[index].conflictId],
                    onChanged: (choice) {
                      setState(() {
                        _choices[conflicts[index].conflictId] = choice;
                      });
                    },
                  ),
                  if (index != conflicts.length - 1)
                    const SizedBox(height: AppSpace.md),
                ],
                const SizedBox(height: AppSpace.lg),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    key: const Key('personal-cloud-conflict-apply'),
                    onPressed:
                        !_isBusy(cloud) && _choices.length == conflicts.length
                            ? () => _apply(cloud)
                            : null,
                    icon: _applying
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.merge_outlined),
                    label: Text(context.l10n.personalCloudConflictApply),
                  ),
                ),
              ],
            ),
    );
  }

  bool _isBusy(PersonalCloudProvider cloud) => _applying || cloud.isBusy;

  void _selectAll(
    List<PersonalCloudMergeConflict> conflicts,
    PersonalCloudConflictChoice choice,
  ) {
    setState(() {
      for (final conflict in conflicts) {
        _choices[conflict.conflictId] = choice;
      }
    });
  }

  Future<void> _apply(PersonalCloudProvider cloud) async {
    setState(() => _applying = true);
    try {
      await cloud.resolvePendingConflicts(Map.unmodifiable(_choices));
      if (!mounted) return;
      if (cloud.conflicts.isEmpty) {
        _choices.clear();
        context.showLoggedSnackBar(
          SnackBar(
            content: Text(
              context.l10n.personalCloudConflictApplySucceeded,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudError('$error'))),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

class _EmptyConflictState extends StatelessWidget {
  const _EmptyConflictState({
    required this.confirmationPending,
    required this.onOpenDatabase,
  });

  final bool confirmationPending;
  final VoidCallback onOpenDatabase;

  @override
  Widget build(BuildContext context) => AppSectionCard(
        key: const Key('personal-cloud-no-conflicts'),
        icon: confirmationPending
            ? Icons.info_outline
            : Icons.cloud_done_outlined,
        title: confirmationPending
            ? context.l10n.personalCloudConflictConfirmationPendingTitle
            : context.l10n.personalCloudConflictNoneTitle,
        description: confirmationPending
            ? context.l10n.personalCloudConflictConfirmationPendingHint
            : context.l10n.personalCloudConflictNoneHint,
        tone: confirmationPending ? AppTone.warning : AppTone.success,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            key: const Key('personal-cloud-open-database'),
            onPressed: onOpenDatabase,
            icon: const Icon(Icons.storage_outlined),
            label: Text(context.l10n.dataLocalDatabaseTab),
          ),
        ),
      );
}

class _PersonalCloudConflictCard extends StatelessWidget {
  const _PersonalCloudConflictCard({
    required this.conflict,
    required this.choice,
    required this.onChanged,
  });

  final PersonalCloudMergeConflict conflict;
  final PersonalCloudConflictChoice? choice;
  final ValueChanged<PersonalCloudConflictChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final entity = switch (conflict.entityType) {
      'session' => context.l10n.personalCloudEntitySession,
      'dictionaryItem' => context.l10n.personalCloudEntityDictionaryItem,
      _ => context.l10n.personalCloudEntityLog,
    };
    final field = _fieldLabel(context, conflict.fieldGroup);
    final title = conflict.kind == 'fieldConflict' || field != null
        ? context.l10n.personalCloudFieldConflictTitle(field ?? entity)
        : context.l10n.personalCloudEntityConflictTitle(entity);
    final dataset = conflict.dataset == PersonalCloudDataset.records
        ? context.l10n.personalCloudConflictRecordsDataset
        : context.l10n.personalCloudConflictDictionaryDataset;

    return AppSectionCard(
      key: Key('personal-cloud-conflict-${conflict.conflictId}'),
      icon: conflict.dataset == PersonalCloudDataset.records
          ? Icons.description_outlined
          : Icons.menu_book_outlined,
      title: title,
      description: context.l10n.personalCloudConflictEntityReference(
        dataset,
        conflict.entityId,
      ),
      style: AppSurfaceStyle.outlined,
      tone: AppTone.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (conflict.basePresent) ...[
            _BaselineValue(value: conflict.baseValue),
            const SizedBox(height: AppSpace.sm),
          ],
          RadioGroup<PersonalCloudConflictChoice>(
            groupValue: choice,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final local = _ConflictChoiceTile(
                  key: Key('conflict-local-${conflict.conflictId}'),
                  title: context.l10n.personalCloudKeepLocal,
                  icon: Icons.laptop_outlined,
                  value: PersonalCloudConflictChoice.local,
                  selected: choice == PersonalCloudConflictChoice.local,
                  displayValue: _displayValue(
                    context,
                    conflict.localValue,
                    present: conflict.localPresent,
                  ),
                );
                final remote = _ConflictChoiceTile(
                  key: Key('conflict-remote-${conflict.conflictId}'),
                  title: context.l10n.personalCloudKeepRemote,
                  icon: Icons.cloud_outlined,
                  value: PersonalCloudConflictChoice.remote,
                  selected: choice == PersonalCloudConflictChoice.remote,
                  displayValue: _displayValue(
                    context,
                    conflict.remoteValue,
                    present: conflict.remotePresent,
                  ),
                );
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      local,
                      const SizedBox(height: AppSpace.sm),
                      remote,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: local),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: remote),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String? _fieldLabel(BuildContext context, String? rawField) {
    if (rawField == null) return null;
    final field = rawField.startsWith('immutable:')
        ? rawField.substring('immutable:'.length)
        : rawField;
    return switch (field) {
      'time' => context.l10n.fieldTime,
      'controller' => context.l10n.fieldControllerCallsign,
      'callsign' => context.l10n.fieldCallsign,
      'rst_sent' => context.l10n.fieldRstSent,
      'rst_rcvd' => context.l10n.fieldRstRcvd,
      'qth' => context.l10n.fieldQth,
      'device' => context.l10n.fieldDevice,
      'power' => context.l10n.fieldPower,
      'antenna' => context.l10n.fieldAntenna,
      'height' => context.l10n.fieldHeight,
      'remarks' => context.l10n.fieldRemarks,
      'title' => context.l10n.sessionTitleLabel,
      'lifecycle' => context.l10n.personalCloudConflictLifecycleField,
      'deletion' => context.l10n.personalCloudConflictDeletionField,
      'state' => context.l10n.personalCloudConflictDictionaryStateField,
      _ => field.replaceAll('_', ' '),
    };
  }

  static String _displayValue(
    BuildContext context,
    Object? value, {
    required bool present,
  }) {
    if (!present) return context.l10n.personalCloudConflictValueAbsent;
    if (value == null || value == '') {
      return context.l10n.personalCloudConflictValueEmpty;
    }
    final String text;
    if (value is Map || value is List) {
      text = const JsonEncoder.withIndent('  ').convert(value);
    } else {
      text = value.toString();
    }
    return text.length > 1200 ? '${text.substring(0, 1200)}\u2026' : text;
  }
}

class _BaselineValue extends StatelessWidget {
  const _BaselineValue({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.personalCloudConflictBaseline,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpace.xxs),
          SelectableText(
            _PersonalCloudConflictCard._displayValue(
              context,
              value,
              present: true,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ConflictChoiceTile extends StatelessWidget {
  const _ConflictChoiceTile({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.selected,
    required this.displayValue,
  });

  final String title;
  final IconData icon;
  final PersonalCloudConflictChoice value;
  final bool selected;
  final String displayValue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(
          color: selected ? colors.secondary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RadioListTile<PersonalCloudConflictChoice>(
        value: value,
        secondary: Icon(
          icon,
          color:
              selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(
            displayValue,
            maxLines: 12,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ),
        isThreeLine: true,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.sm,
          AppSpace.xs,
          AppSpace.sm,
          AppSpace.xs,
        ),
      ),
    );
  }
}
