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
    expect(find.byIcon(Icons.delete_sweep_outlined), findsNWidgets(4));

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

    await tester.tap(
      find.descendant(of: deviceCard, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: deviceCard, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    final reopenedSearch = tester.widget<TextField>(search);
    expect(reopenedSearch.controller?.text, 'not-found');
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
    expect(find.byIcon(Icons.delete_sweep_outlined), findsNWidgets(4));
  });

  testWidgets('single entry deletion requires confirmation and refreshes UI',
      (tester) async {
    final provider = _TestDictionaryProvider();
    await _pumpManager(tester, provider);
    await _expandDeviceLibrary(tester);

    final deviceCard = find.byKey(const Key('library-card-device'));
    await tester.tap(
      find.descendant(
        of: deviceCard,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('删除词库条目'), findsOneWidget);
    expect(provider.deletedValues, isEmpty);
    await tester.tap(
      find.byKey(const Key('confirm-delete-library-item-device')),
    );
    await tester.pumpAndSettle();

    expect(provider.deletedValues, const <String>['FT-991A']);
    expect(provider.deviceDict, isEmpty);
    expect(find.text('词库中还没有内容'), findsOneWidget);
  });

  testWidgets('clear by type requires confirmation and refreshes its count',
      (tester) async {
    final provider = _TestDictionaryProvider();
    await _pumpManager(tester, provider);
    await _expandDeviceLibrary(tester);
    await tester.enterText(
      find.byKey(const Key('search-library-device')),
      'FT',
    );

    await tester.tap(find.byKey(const Key('clear-library-device')));
    await tester.pumpAndSettle();
    expect(find.text('清空设备词库'), findsOneWidget);
    expect(find.textContaining('全部 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('confirm-clear-library-device')),
    );
    await tester.pumpAndSettle();

    expect(provider.clearedTypes, const <String>['device']);
    expect(find.text('设备词库 · 0'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('search-library-device')),
          )
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('delete failure leaves entry visible and explains the failure',
      (tester) async {
    final provider = _TestDictionaryProvider(failDelete: true);
    await _pumpManager(tester, provider);
    await _expandDeviceLibrary(tester);
    final deviceCard = find.byKey(const Key('library-card-device'));

    await tester.tap(
      find.descendant(
        of: deviceCard,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-delete-library-item-device')),
    );
    await tester.pump();

    expect(find.text('FT-991A'), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });

  testWidgets('narrow phone layout keeps library actions on screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _TestDictionaryProvider();

    await _pumpManager(tester, provider, width: 360);
    await _expandDeviceLibrary(tester);

    expect(find.byKey(const Key('import-library-json')), findsOneWidget);
    expect(find.byKey(const Key('clear-library-device')), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpManager(
  WidgetTester tester,
  DictionaryProvider provider, {
  double width = 700,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DictionaryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: const DictionaryManager()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _expandDeviceLibrary(WidgetTester tester) async {
  final deviceCard = find.byKey(const Key('library-card-device'));
  await tester.tap(
    find.descendant(of: deviceCard, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

class _TestDictionaryProvider extends DictionaryProvider {
  _TestDictionaryProvider({this.failDelete = false}) : super(autoload: false);

  final bool failDelete;
  final List<String> deletedValues = <String>[];
  final List<String> clearedTypes = <String>[];

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

  @override
  Future<void> deleteDevice(String raw) async {
    if (failDelete) throw StateError('simulated persistent delete failure');
    deletedValues.add(raw);
    _devices.removeWhere((item) => item.raw == raw);
    notifyListeners();
  }

  @override
  Future<void> clearDeviceDict() async {
    clearedTypes.add('device');
    _devices.clear();
    notifyListeners();
  }
}
