import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:provider/provider.dart';

/// Presents the appropriate way to continue locally from the current
/// collaboration session.
///
/// A synchronized session can be converted directly. When direct conversion
/// is unavailable, the action remains visible as a disaster-recovery copy of
/// the materialized local replica.
class CollaborationLocalSessionAction extends StatelessWidget {
  const CollaborationLocalSessionAction({
    super.key,
    this.padding = EdgeInsets.zero,
    this.alignment,
  });

  final EdgeInsetsGeometry padding;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final collaboration = context.watch<CollaborationProvider>();
    final session = context.watch<SessionProvider>().currentSession;
    final binding = collaboration.binding;
    if (session == null ||
        binding == null ||
        binding.sessionId != session.sessionId) {
      return const SizedBox.shrink();
    }

    final convertDirectly = collaboration.canConvertCurrentSessionDirectly;
    final action = OutlinedButton.icon(
      key: Key(
        convertDirectly
            ? 'convert-collaboration-to-local'
            : 'create-editable-local-copy',
      ),
      onPressed: collaboration.isBusy
          ? null
          : () => _confirmAndRun(
                context,
                collaboration: collaboration,
                sourceTitle: session.title,
                convertDirectly: convertDirectly,
              ),
      icon: Icon(
        convertDirectly ? Icons.cloud_off_outlined : Icons.copy_all_outlined,
      ),
      label: Text(
        convertDirectly
            ? context.l10n.convertCollaborationToLocal
            : context.l10n.createEditableLocalCopy,
      ),
    );

    return Padding(
      padding: padding,
      child: alignment == null
          ? action
          : Align(alignment: alignment!, child: action),
    );
  }

  Future<void> _confirmAndRun(
    BuildContext context, {
    required CollaborationProvider collaboration,
    required String sourceTitle,
    required bool convertDirectly,
  }) async {
    final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: Key(
              convertDirectly
                  ? 'convert-collaboration-to-local-dialog'
                  : 'create-editable-local-copy-dialog',
            ),
            title: Text(
              convertDirectly
                  ? context.l10n.convertCollaborationToLocalTitle
                  : context.l10n.createEditableLocalCopyTitle,
            ),
            content: Text(
              convertDirectly
                  ? context.l10n.convertCollaborationToLocalConfirmation(
                      sourceTitle,
                    )
                  : context.l10n.createEditableLocalCopyConfirmation(
                      sourceTitle,
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                key: Key(
                  convertDirectly
                      ? 'confirm-convert-collaboration-to-local'
                      : 'confirm-create-editable-local-copy',
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  convertDirectly
                      ? context.l10n.convertCollaborationToLocal
                      : context.l10n.createEditableLocalCopy,
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!accepted || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final successMessage = convertDirectly
        ? context.l10n.convertCollaborationToLocalSucceeded
        : context.l10n.editableLocalCopySucceeded;
    try {
      if (convertDirectly) {
        await collaboration.convertCurrentSessionToLocal();
      } else {
        await collaboration.createEditableLocalCopy(
          title: _editableLocalCopyTitle(context, sourceTitle),
        );
      }
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.operationFailed('$error'))),
        );
      }
    }
  }

  String _editableLocalCopyTitle(BuildContext context, String sourceTitle) {
    final sourceRunes = sourceTitle.trim().runes.toList(growable: true);
    var localTitle = context.l10n.editableLocalCopySessionTitle(
      String.fromCharCodes(sourceRunes),
    );
    while (localTitle.runes.length > 200 && sourceRunes.isNotEmpty) {
      sourceRunes.removeLast();
      localTitle = context.l10n.editableLocalCopySessionTitle(
        String.fromCharCodes(sourceRunes),
      );
    }
    return localTitle.runes.length > 200
        ? String.fromCharCodes(localTitle.runes.take(200))
        : localTitle;
  }
}
