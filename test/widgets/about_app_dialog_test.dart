import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/about_app_dialog.dart';

void main() {
  testWidgets('shows complete app and project information in zh_CN',
      (tester) async {
    await _setSurface(tester, const Size(800, 760));

    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('zh', 'CN'),
        launcher: (_) async => true,
      ),
    );
    await tester.tap(find.byKey(const Key('open-about')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-app-dialog')), findsOneWidget);
    expect(find.text('OpenLogTool'), findsOneWidget);
    expect(find.text('版本 2.1.0-R+42'), findsOneWidget);
    expect(find.text('2.1.0-R+42'), findsOneWidget);
    expect(find.text('418'), findsOneWidget);
    expect(find.text('abc1234'), findsOneWidget);
    expect(find.text('GNU AGPL-3.0'), findsOneWidget);
    expect(find.byKey(const Key('about-repository')), findsOneWidget);
    expect(find.byKey(const Key('about-issues')), findsOneWidget);
    expect(find.byKey(const Key('about-licenses')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('about-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about-app-dialog')), findsNothing);
  });

  testWidgets('fits a narrow English screen and opens the repository',
      (tester) async {
    await _setSurface(tester, const Size(320, 568));
    Uri? openedUri;

    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('en', 'US'),
        textScaleFactor: 2,
        launcher: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('open-about')));
    await tester.pumpAndSettle();

    expect(find.text('OpenLogTool'), findsOneWidget);
    expect(find.byKey(const Key('about-app-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final repository = find.byKey(const Key('about-repository'));
    await tester.ensureVisible(repository);
    await tester.tap(repository);
    await tester.pump();

    expect(openedUri, AboutAppDialog.repositoryUri);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('about-licenses')));
    expect(find.byKey(const Key('about-close')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about-app-dialog')), findsNothing);
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.locale,
    required this.launcher,
    this.textScaleFactor = 1,
  });

  final Locale locale;
  final AboutLinkLauncher launcher;
  final double textScaleFactor;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('open-about'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AboutAppDialog(
                    appName: 'OpenLogTool',
                    fullVersion: '2.1.0-R+42',
                    buildNumber: '418',
                    commitHash: 'abc1234',
                    linkLauncher: launcher,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
}
