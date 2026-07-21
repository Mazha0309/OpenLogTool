import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'owner sees a localized explanation when Live Share is unsupported',
      (tester) async {
    final collaboration = _PublicShareCollaborationProvider(supported: false);
    await _pumpScreen(
      tester,
      collaboration: collaboration,
      locale: const Locale('zh', 'CN'),
    );

    expect(find.text('Live Share · 公开只读页面'), findsOneWidget);
    expect(find.byKey(const Key('public-share-unsupported')), findsOneWidget);
    expect(find.byKey(const Key('create-public-share-link')), findsNothing);
  });

  testWidgets('owner can create, copy, and open a Live Share page',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final collaboration = _PublicShareCollaborationProvider(supported: true);
    Uri? openedUri;
    await _pumpScreen(
      tester,
      collaboration: collaboration,
      locale: const Locale('en', 'US'),
      opener: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    expect(find.byKey(const Key('public-share-empty')), findsOneWidget);
    final createButton = find.byKey(const Key('create-public-share-link'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('public-share-expiry-dialog')),
      findsOneWidget,
    );
    expect(collaboration.createCount, 0);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('public-share-expiry-24')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const Key('public-share-estimated-expiry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-public-share-expiry')));
    await tester.pumpAndSettle();

    expect(collaboration.createCount, 1);
    expect(collaboration.lastExpiresInHours, 24);
    expect(find.byKey(const Key('public-share-ready')), findsOneWidget);
    expect(copiedText, _publicUri.toString());

    final copyButton = find.byKey(const Key('copy-public-share-link'));
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(copiedText, _publicUri.toString());

    final openButton = find.byKey(const Key('open-public-share-link'));
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    expect(openedUri, _publicUri);
  });

  testWidgets('expiry dialog offers presets and validates custom hours',
      (tester) async {
    final collaboration = _PublicShareCollaborationProvider(supported: true);
    await _pumpScreen(
      tester,
      collaboration: collaboration,
      locale: const Locale('zh', 'CN'),
    );

    final createButton = find.byKey(const Key('create-public-share-link'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    for (final label in ['1小时', '6小时', '12小时', '1天', '3天', '7天', '30天']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('public-share-expiry-custom')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('public-share-estimated-expiry')),
      findsNothing,
    );

    final customHours = find.byKey(const Key('public-share-custom-hours'));
    await tester.enterText(customHours, '721');
    await tester.pump();
    expect(find.text('请输入 1–720 之间的整数小时'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-public-share-expiry')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(customHours, '36');
    await tester.pump();
    expect(
      find.byKey(const Key('public-share-estimated-expiry')),
      findsOneWidget,
    );
    final confirm = find.byKey(const Key('confirm-public-share-expiry'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(collaboration.createCount, 1);
    expect(collaboration.lastExpiresInHours, 36);
  });

  testWidgets('an active link without its one-time secret explains recovery',
      (tester) async {
    final collaboration = _PublicShareCollaborationProvider(
      supported: true,
      shares: [_share(secret: null)],
    );
    await _pumpScreen(
      tester,
      collaboration: collaboration,
      locale: const Locale('en', 'US'),
    );

    expect(
      find.byKey(const Key('public-share-secret-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('copy-public-share-link')), findsNothing);
    expect(find.byKey(const Key('open-public-share-link')), findsNothing);
    expect(find.byKey(const Key('create-public-share-link')), findsOneWidget);
  });
}

final _publicUri = Uri(
  scheme: 'https',
  host: 'example.test',
  path: '/live/share-1',
  fragment: 'one-time-secret',
);

PublicShareDto _share({required String? secret}) => PublicShareDto(
      publicShareId: 'share-1',
      sessionId: 'session-1',
      expiresAt: DateTime.utc(2099),
      createdBy: 'user-1',
      createdAt: DateTime.utc(2026, 7, 13),
      revokedAt: null,
      revokedBy: null,
      secret: secret,
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _PublicShareCollaborationProvider collaboration,
  required Locale locale,
  PublicShareUriOpener? opener,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollaborationScreen(
          publicShareUriOpener: opener,
          focusPublicShare: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _PublicShareCollaborationProvider extends CollaborationProvider {
  _PublicShareCollaborationProvider({
    required this.supported,
    List<PublicShareDto> shares = const [],
  }) : testShares = shares;

  final bool supported;
  List<PublicShareDto> testShares;
  PublicShareDto? createdShare;
  int createCount = 0;
  int? lastExpiresInHours;

  @override
  CollaborationState get state => CollaborationState.ready;

  @override
  bool get isOwner => true;

  @override
  bool get canJoinWithInvite => false;

  @override
  bool get supportsInvites => false;

  @override
  bool get supportsPublicShareManagement => supported;

  @override
  List<PublicShareDto> get publicShares => testShares;

  @override
  PublicShareDto? get lastCreatedPublicShare => createdShare;

  @override
  Future<void> refreshCurrentSession() async {}

  @override
  Future<void> refreshPublicShares() async {}

  @override
  Future<PublicShareDto> createPublicShare({int expiresInHours = 24}) async {
    createCount += 1;
    lastExpiresInHours = expiresInHours;
    final share = _share(secret: 'one-time-secret');
    createdShare = share;
    testShares = [share];
    notifyListeners();
    return share;
  }

  @override
  Uri publicSharePageUri(PublicShareDto share) => _publicUri;
}

class _LoggedInServerProvider extends ServerProvider {
  _LoggedInServerProvider() : super(autoLoadSettings: false);

  @override
  bool get isLoggedIn => true;

  @override
  String get serverUrl => 'https://example.test';

  @override
  String? get accountId => 'user-1';

  @override
  String? get username => 'owner';
}

class _TestSessionProvider extends SessionProvider {
  static const session = Session(
    sessionId: 'session-1',
    title: 'Public session',
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
