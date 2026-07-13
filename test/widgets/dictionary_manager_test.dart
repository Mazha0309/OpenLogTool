import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/widgets/dictionary_manager.dart';
import 'package:provider/provider.dart';

void main() {
  test('zh_CN and en_US use library terminology consistently', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final en = await AppLocalizations.delegate.load(const Locale('en', 'US'));

    expect(zh.dictionaryManagementTitle, '词库管理');
    expect(zh.deviceLibrary, '设备词库');
    expect(en.dictionaryManagementTitle, 'Lookup libraries');
    expect(en.deviceLibrary, 'Radio library');
  });

  test('dictionary grid uses two columns only when space is available', () {
    expect(dictionaryGridColumnCount(759), 1);
    expect(dictionaryGridColumnCount(760), 2);
  });

  testWidgets('library management uses consistent terminology and search',
      (tester) async {
    final provider = _TestDictionaryProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<DictionaryProvider>.value(
        value: provider,
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: 700, child: DictionaryManager()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('词库管理'), findsOneWidget);
    expect(find.textContaining('词典'), findsNothing);
    expect(find.byKey(const Key('import-library-json')), findsOneWidget);
    expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);

    final deviceTop = tester.getTopLeft(
      find.byKey(const Key('library-card-device')),
    );
    final antennaTop = tester.getTopLeft(
      find.byKey(const Key('library-card-antenna')),
    );
    expect(antennaTop.dy, greaterThan(deviceTop.dy));

    final deviceCard = find.byKey(const Key('library-card-device'));
    await tester.tap(
      find.descendant(of: deviceCard, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('search-library-device'));
    expect(search, findsOneWidget);
    expect(find.text('FT-991A'), findsOneWidget);
    await tester.enterText(search, 'not-found');
    await tester.pump();
    expect(find.text('没有匹配的词库内容'), findsOneWidget);
  });

  testWidgets('wide library management lays cards out in two columns',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _TestDictionaryProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<DictionaryProvider>.value(
        value: provider,
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(width: 900, child: DictionaryManager()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final deviceTop = tester.getTopLeft(
      find.byKey(const Key('library-card-device')),
    );
    final antennaTop = tester.getTopLeft(
      find.byKey(const Key('library-card-antenna')),
    );
    expect(antennaTop.dy, deviceTop.dy);
    expect(antennaTop.dx, greaterThan(deviceTop.dx));
    expect(find.text('Lookup libraries'), findsOneWidget);
    expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
  });
}

class _TestDictionaryProvider extends DictionaryProvider {
  _TestDictionaryProvider() : super(autoload: false);

  final List<DictionaryItem> _devices = <DictionaryItem>[
    DictionaryItem(
      raw: 'FT-991A',
      pinyin: '',
      abbreviation: 'FT991A',
      type: 'device_dictionary',
    ),
  ];

  @override
  List<DictionaryItem> get deviceDict => _devices;

  @override
  List<DictionaryItem> get antennaDict => const <DictionaryItem>[];

  @override
  List<DictionaryItem> get callsignDict => const <DictionaryItem>[];

  @override
  List<DictionaryItem> get qthDict => const <DictionaryItem>[];
}
