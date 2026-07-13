import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/widgets/session_title_editor.dart';

void main() {
  test('local active sessions can be renamed', () {
    expect(
      sessionRenameAvailability(
        sessionStatus: 'active',
        collaborationState: CollaborationState.localOnly,
        hasCollaborationBinding: false,
        isCollaborationOwner: false,
        isBusy: false,
        hasOpenSessionConflict: false,
      ),
      SessionRenameAvailability.allowed,
    );
  });

  test('collaboration rename requires a ready conflict-free owner', () {
    SessionRenameAvailability availability({
      bool owner = true,
      bool busy = false,
      bool conflict = false,
      CollaborationState state = CollaborationState.ready,
    }) =>
        sessionRenameAvailability(
          sessionStatus: 'active',
          collaborationState: state,
          hasCollaborationBinding: true,
          isCollaborationOwner: owner,
          isBusy: busy,
          hasOpenSessionConflict: conflict,
        );

    expect(availability(), SessionRenameAvailability.allowed);
    expect(
      availability(owner: false),
      SessionRenameAvailability.ownerRequired,
    );
    expect(
      availability(busy: true),
      SessionRenameAvailability.collaborationBusy,
    );
    expect(
      availability(conflict: true),
      SessionRenameAvailability.collaborationConflict,
    );
    expect(
      availability(state: CollaborationState.resyncing),
      SessionRenameAvailability.collaborationNotReady,
    );
  });

  testWidgets('rename dialog validates changes and renders in en_US',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionRenameDialog(
            currentTitle: 'Sunday Net',
            collaborationSession: true,
          ),
        ),
      ),
    );

    expect(find.text('Rename session'), findsOneWidget);
    expect(find.text('Session name'), findsOneWidget);
    expect(find.textContaining('Only the session owner'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('save-session-title')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('session-title-field')),
      'Updated Sunday Net',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('save-session-title')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
