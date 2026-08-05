import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/utils/personal_cloud_merge.dart';

/// 云同步冲突逐项处理弹窗：字段冲突（fieldConflict）逐字段选择本地/远程，
/// 其他冲突（session 等）显示实体并二选一。
class PersonalCloudConflictDialog extends StatefulWidget {
  const PersonalCloudConflictDialog({
    super.key,
    required this.conflicts,
  });

  final List<PersonalCloudMergeConflict> conflicts;

  @override
  State<PersonalCloudConflictDialog> createState() =>
      _PersonalCloudConflictDialogState();
}

class _PersonalCloudConflictDialogState
    extends State<PersonalCloudConflictDialog> {
  late final Map<String, PersonalCloudConflictChoice> _choices = {
    for (final conflict in widget.conflicts)
      conflict.conflictId: PersonalCloudConflictChoice.local,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const Key('personal-cloud-conflict-dialog'),
      title: Text(l10n.personalCloudConflictDialogTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final conflict in widget.conflicts) ...[
                _ConflictRow(
                  conflict: conflict,
                  choice: _choices[conflict.conflictId]!,
                  onChanged: (choice) {
                    setState(() {
                      _choices[conflict.conflictId] = choice;
                    });
                  },
                ),
                const Divider(height: 24),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('personal-cloud-conflict-apply'),
          onPressed: () => Navigator.pop(context, _choices),
          child: Text(l10n.personalCloudConflictApply),
        ),
      ],
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.conflict,
    required this.choice,
    required this.onChanged,
  });

  final PersonalCloudMergeConflict conflict;
  final PersonalCloudConflictChoice choice;
  final ValueChanged<PersonalCloudConflictChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localValue = _displayValue(conflict.localValue);
    final remoteValue = _displayValue(conflict.remoteValue);

    final String title;
    if (conflict.kind == 'fieldConflict') {
      title = l10n.personalCloudFieldConflictTitle(conflict.fieldGroup ?? '');
    } else {
      title = l10n.personalCloudEntityConflictTitle(
        conflict.entityType == 'session'
            ? l10n.personalCloudEntitySession
            : l10n.personalCloudEntityLog,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        RadioGroup<PersonalCloudConflictChoice>(
          groupValue: choice,
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<PersonalCloudConflictChoice>(
                key: Key('conflict-local-${conflict.conflictId}'),
                title: Text(
                  '${l10n.personalCloudKeepLocal}：$localValue',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: PersonalCloudConflictChoice.local,
              ),
              RadioListTile<PersonalCloudConflictChoice>(
                key: Key('conflict-remote-${conflict.conflictId}'),
                title: Text(
                  '${l10n.personalCloudKeepRemote}：$remoteValue',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: PersonalCloudConflictChoice.remote,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _displayValue(Object? value) {
    if (value == null || value == '') return '—';
    final text = value.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }
}
