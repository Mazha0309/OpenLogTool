import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';

enum SessionRenameAvailability {
  allowed,
  sessionClosed,
  collaborationBusy,
  collaborationConflict,
  collaborationNotReady,
  ownerRequired,
}

SessionRenameAvailability sessionRenameAvailability({
  required String sessionStatus,
  required CollaborationState collaborationState,
  required bool hasCollaborationBinding,
  required bool isCollaborationOwner,
  required bool isBusy,
  required bool hasOpenSessionConflict,
}) {
  if (sessionStatus != 'active') {
    return SessionRenameAvailability.sessionClosed;
  }
  if (!hasCollaborationBinding &&
      collaborationState == CollaborationState.localOnly) {
    return SessionRenameAvailability.allowed;
  }
  if (isBusy) {
    return SessionRenameAvailability.collaborationBusy;
  }
  if (hasOpenSessionConflict) {
    return SessionRenameAvailability.collaborationConflict;
  }
  if (!hasCollaborationBinding ||
      collaborationState != CollaborationState.ready) {
    return SessionRenameAvailability.collaborationNotReady;
  }
  if (!isCollaborationOwner) {
    return SessionRenameAvailability.ownerRequired;
  }
  return SessionRenameAvailability.allowed;
}

String sessionRenameAvailabilityLabel(
  AppLocalizations l10n,
  SessionRenameAvailability availability,
) =>
    switch (availability) {
      SessionRenameAvailability.allowed => l10n.renameSession,
      SessionRenameAvailability.sessionClosed =>
        l10n.renameSessionBlockedClosed,
      SessionRenameAvailability.collaborationBusy =>
        l10n.renameSessionBlockedBusy,
      SessionRenameAvailability.collaborationConflict =>
        l10n.renameSessionBlockedConflict,
      SessionRenameAvailability.collaborationNotReady =>
        l10n.renameSessionBlockedNotReady,
      SessionRenameAvailability.ownerRequired => l10n.renameSessionBlockedOwner,
    };

Future<String?> showSessionRenameDialog(
  BuildContext context, {
  required String currentTitle,
  required bool collaborationSession,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => SessionRenameDialog(
        currentTitle: currentTitle,
        collaborationSession: collaborationSession,
      ),
    );

class SessionRenameDialog extends StatefulWidget {
  const SessionRenameDialog({
    super.key,
    required this.currentTitle,
    required this.collaborationSession,
  });

  final String currentTitle;
  final bool collaborationSession;

  @override
  State<SessionRenameDialog> createState() => _SessionRenameDialogState();
}

class _SessionRenameDialogState extends State<SessionRenameDialog> {
  late final TextEditingController _controller;

  String get _normalizedTitle => _controller.text.trim();

  bool get _canSave =>
      _normalizedTitle.isNotEmpty &&
      _normalizedTitle.length <= 200 &&
      _normalizedTitle != widget.currentTitle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_canSave) Navigator.of(context).pop(_normalizedTitle);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.renameSessionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('session-title-field'),
              controller: _controller,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: context.l10n.sessionTitleLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            if (widget.collaborationSession)
              Text(
                context.l10n.renameCollaborationSessionHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('save-session-title'),
          onPressed: _canSave ? _save : null,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
