import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';

final class CollaborationConflictCenter extends StatelessWidget {
  const CollaborationConflictCenter({
    required this.conflicts,
    required this.loading,
    required this.resolvingConflictId,
    required this.enabled,
    required this.onRefresh,
    required this.onAcceptRemote,
    required this.onKeepLocal,
    required this.onCopyLocalAsNew,
    super.key,
  });

  final List<CollaborationConflict> conflicts;
  final bool loading;
  final String? resolvingConflictId;
  final bool enabled;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onAcceptRemote;
  final ValueChanged<String> onKeepLocal;
  final ValueChanged<String> onCopyLocalAsNew;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('collaboration-conflict-center'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.conflictCenterTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    key: const Key('refresh-conflicts'),
                    tooltip: context.l10n.refreshConflicts,
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            Text(context.l10n.conflictCenterHint),
            const SizedBox(height: 8),
            if (conflicts.isEmpty && !loading)
              Text(context.l10n.noConflicts)
            else
              ...conflicts.map((conflict) => _ConflictTile(
                    conflict: conflict,
                    resolving: resolvingConflictId == conflict.conflictId,
                    enabled: enabled,
                    onAcceptRemote: onAcceptRemote,
                    onKeepLocal: onKeepLocal,
                    onCopyLocalAsNew: onCopyLocalAsNew,
                  )),
          ],
        ),
      ),
    );
  }
}

final class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.resolving,
    required this.enabled,
    required this.onAcceptRemote,
    required this.onKeepLocal,
    required this.onCopyLocalAsNew,
  });

  final CollaborationConflict conflict;
  final bool resolving;
  final bool enabled;
  final ValueChanged<String> onAcceptRemote;
  final ValueChanged<String> onKeepLocal;
  final ValueChanged<String> onCopyLocalAsNew;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (conflict.entityType) {
      CollaborationConflictEntityType.session => context.l10n.conflictSession,
      CollaborationConflictEntityType.log => context.l10n.conflictLog,
    };
    final fields = conflict.conflictingFields.isEmpty
        ? context.l10n.conflictNoOverlappingFields
        : conflict.conflictingFields.join(context.l10n.listSeparator);
    final allowsRemote = conflict.allowedResolutions.contains(
      CollaborationConflictResolution.useRemote,
    );
    final allowsKeepLocal = conflict.allowedResolutions.contains(
      CollaborationConflictResolution.keepLocal,
    );
    final allowsCopy = conflict.allowedResolutions.contains(
      CollaborationConflictResolution.copyLocalAsNew,
    );
    return ExpansionTile(
      key: Key('conflict-${conflict.conflictId}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: Text('$typeLabel · ${conflict.entityId}'),
      subtitle: Text(
        context.l10n.conflictVersionSummary(
          fields,
          conflict.baseVersion,
          conflict.remoteVersion,
        ),
      ),
      leading: resolving
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.merge_type),
      children: [
        _summary(context, context.l10n.conflictBase, conflict.baseEntity),
        _summary(context, context.l10n.conflictLocal, conflict.localEntity),
        _summary(context, context.l10n.conflictRemote, conflict.remoteEntity),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (allowsRemote)
              OutlinedButton.icon(
                key: Key('accept-remote-${conflict.conflictId}'),
                onPressed: resolving || !enabled
                    ? null
                    : () => onAcceptRemote(conflict.conflictId),
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(context.l10n.conflictUseRemoteAction),
              ),
            if (allowsKeepLocal)
              FilledButton.tonalIcon(
                key: Key('keep-local-${conflict.conflictId}'),
                onPressed: resolving || !enabled
                    ? null
                    : () => onKeepLocal(conflict.conflictId),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(context.l10n.conflictKeepLocalAction),
              ),
            if (allowsCopy)
              FilledButton.tonalIcon(
                key: Key('copy-local-${conflict.conflictId}'),
                onPressed: resolving || !enabled
                    ? null
                    : () => onCopyLocalAsNew(conflict.conflictId),
                icon: const Icon(Icons.content_copy),
                label: Text(context.l10n.conflictCopyLocalAction),
              ),
          ],
        ),
      ],
    );
  }

  Widget _summary(
    BuildContext context,
    String label,
    Map<String, Object?>? entity,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: SelectableText(
                collaborationConflictEntitySummary(entity),
              ),
            ),
          ],
        ),
      );
}
