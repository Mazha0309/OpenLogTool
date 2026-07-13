import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/screens/collaboration_screen.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('invite joining remains available for revoked and failed rejoin states',
      () {
    final binding = _binding();
    final revoked = _TestCollaborationProvider(
      binding: binding,
      state: CollaborationState.revoked,
    );
    final failedRejoin = _TestCollaborationProvider(
      binding: binding,
      state: CollaborationState.failed,
      failedOperation: 'join',
    );
    final ready = _TestCollaborationProvider(
      binding: binding,
      state: CollaborationState.ready,
    );
    final firstJoin = _TestCollaborationProvider(
      binding: null,
      state: CollaborationState.localOnly,
    );
    addTearDown(revoked.dispose);
    addTearDown(failedRejoin.dispose);
    addTearDown(ready.dispose);
    addTearDown(firstJoin.dispose);

    expect(revoked.canJoinWithInvite, isTrue);
    expect(failedRejoin.canJoinWithInvite, isTrue);
    expect(firstJoin.canJoinWithInvite, isTrue);
    expect(ready.canJoinWithInvite, isFalse);
  });

  testWidgets('a revoked member can submit a new invite from the bound session',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collaboration = _TestCollaborationProvider(
      binding: _binding(),
      state: CollaborationState.revoked,
    );
    final server = _LoggedInServerProvider();
    final sessions = _TestSessionProvider();
    addTearDown(collaboration.dispose);
    addTearDown(server.dispose);
    addTearDown(sessions.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CollaborationProvider>.value(
            value: collaboration,
          ),
          ChangeNotifierProvider<ServerProvider>.value(value: server),
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CollaborationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('join-collaboration-card')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('collaboration-invite-code')),
      'ABCDE12345',
    );
    final joinButton = find.byKey(const Key('join-collaboration-button'));
    await tester.ensureVisible(joinButton);
    await tester.tap(joinButton);
    await tester.pumpAndSettle();

    expect(collaboration.joinedCodes, ['ABCDE12345']);
  });
}

LocalCollaborationBinding _binding() => const LocalCollaborationBinding(
      serverInstanceId: 'server-1',
      serverOrigin: 'http://127.0.0.1:3000',
      accountId: 'user-1',
      sessionId: 'session-1',
      membershipId: 'membership-1',
      membershipVersion: 2,
      role: SessionRole.viewer,
      // The in-memory binding can still say ready when the sync coordinator
      // has just persisted revocation and changed the provider state.
      replicaState: 'ready',
      lastAppliedSeq: 4,
      lastSeenHeadSeq: 4,
      revokedAt: null,
    );

class _TestCollaborationProvider extends CollaborationProvider {
  _TestCollaborationProvider({
    required LocalCollaborationBinding? binding,
    required CollaborationState state,
    String? failedOperation,
  })  : testBinding = binding,
        testState = state,
        testFailedOperation = failedOperation;

  final LocalCollaborationBinding? testBinding;
  final CollaborationState testState;
  final String? testFailedOperation;
  final List<String> joinedCodes = [];

  @override
  LocalCollaborationBinding? get binding => testBinding;

  @override
  CollaborationState get state => testState;

  @override
  String? get failedOperation => testFailedOperation;

  @override
  Future<void> refreshCurrentSession() async {}

  @override
  Future<void> joinWithCode(String code) async {
    joinedCodes.add(code);
  }
}

class _LoggedInServerProvider extends ServerProvider {
  _LoggedInServerProvider() : super(autoLoadSettings: false);

  @override
  bool get isLoggedIn => true;

  @override
  String get serverUrl => 'http://127.0.0.1:3000';

  @override
  String? get accountId => 'user-1';

  @override
  String? get username => 'member';
}

class _TestSessionProvider extends SessionProvider {
  _TestSessionProvider();

  static const session = Session(
    sessionId: 'session-1',
    title: 'Revoked session',
    status: 'active',
    createdAt: '2026-07-13T00:00:00Z',
    updatedAt: '2026-07-13T00:00:00Z',
  );

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => session.sessionId;

  @override
  Session get currentSession => session;
}
