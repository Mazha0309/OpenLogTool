import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/widgets/dictionary_manager.dart';
import 'package:provider/provider.dart';

void main() {
  test('dictionary workspace uses responsive page sizes', () {
    expect(dictionaryPageSize(360), 10);
    expect(dictionaryPageSize(719), 10);
    expect(dictionaryPageSize(720), 20);
    expect(dictionaryPageSize(1200), 20);
  });

  testWidgets('phone shows top categories and paginates ten entries',
      (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 25);
    await _pumpManager(tester, provider, width: 360, height: 900);

    expect(find.byKey(const Key('library-phone-categories')), findsOneWidget);
    expect(find.byKey(const Key('library-wide-workspace')), findsNothing);
    expect(find.byKey(const Key('library-workspace-device')), findsOneWidget);
    expect(find.text('Device 01'), findsOneWidget);
    expect(find.text('Device 09'), findsOneWidget);
    expect(find.text('Device 10'), findsNothing);
    expect(find.text('第 1 / 3 页'), findsOneWidget);

    final nextPage = find.byKey(const Key('library-next-page-device'));
    await tester.ensureVisible(nextPage);
    await tester.tap(nextPage);
    await tester.pump();
    expect(find.text('Device 01'), findsNothing);
    expect(find.text('Device 10'), findsOneWidget);
    expect(find.text('Device 19'), findsOneWidget);
    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout keeps categories left and shows twenty entries',
      (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 25);
    await _pumpManager(tester, provider, width: 1100, height: 1000);

    final category = find.byKey(const Key('library-category-device'));
    final workspace = find.byKey(const Key('library-workspace-device'));
    expect(find.byKey(const Key('library-wide-workspace')), findsOneWidget);
    expect(find.byKey(const Key('library-phone-categories')), findsNothing);
    expect(tester.getTopLeft(category).dx,
        lessThan(tester.getTopLeft(workspace).dx));
    expect(find.text('Device 19'), findsOneWidget);
    expect(find.text('Device 20'), findsNothing);
    expect(find.text('第 1 / 2 页'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-category-antenna')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-workspace-antenna')), findsOneWidget);
    expect(find.text('Yagi'), findsOneWidget);
  });

  testWidgets('search matches raw pinyin and abbreviation', (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 1);
    await _pumpManager(tester, provider, width: 700);
    final search = find.byKey(const Key('search-library-device'));

    await tester.enterText(search, 'Handheld');
    await tester.pump();
    expect(find.text('Handheld radio'), findsOneWidget);

    await tester.enterText(search, 'shou tai');
    await tester.pump();
    expect(find.text('Handheld radio'), findsOneWidget);

    await tester.enterText(search, 'ST');
    await tester.pump();
    expect(find.text('Handheld radio'), findsOneWidget);

    await tester.enterText(search, 'not-found');
    await tester.pump();
    expect(find.text('没有匹配的词库内容'), findsOneWidget);
  });

  testWidgets('editing persists before replacing the visible entry',
      (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 1);
    await _pumpManager(tester, provider, width: 700);

    await tester.tap(find.byKey(const Key('edit-library-device-device-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-library-item-field-device')),
      'Renamed radio',
    );
    await tester.tap(
      find.byKey(const Key('confirm-edit-library-item-device')),
    );
    await tester.pumpAndSettle();

    expect(
        provider.renamedValues, const <String>['Handheld radio→Renamed radio']);
    expect(find.text('Renamed radio'), findsOneWidget);
    expect(find.text('Handheld radio'), findsNothing);
  });

  testWidgets('failed edit keeps the original entry visible', (tester) async {
    final provider = _TestDictionaryProvider(
      deviceCount: 1,
      failRename: true,
    );
    await _pumpManager(tester, provider, width: 700);

    await tester.tap(find.byKey(const Key('edit-library-device-device-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-library-item-field-device')),
      'Rejected radio',
    );
    await tester.tap(
      find.byKey(const Key('confirm-edit-library-item-device')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Handheld radio'), findsOneWidget);
    expect(find.text('Rejected radio'), findsNothing);
    expect(find.textContaining('修改失败'), findsOneWidget);
  });

  testWidgets('delete and clear remain confirmed destructive operations',
      (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 2);
    await _pumpManager(tester, provider, width: 700);

    await tester.tap(find.byKey(const Key('delete-library-device-device-0')));
    await tester.pumpAndSettle();
    expect(find.text('删除词库条目'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('confirm-delete-library-item-device')),
    );
    await tester.pumpAndSettle();
    expect(provider.deletedValues, const <String>['Handheld radio']);

    await tester.tap(find.byKey(const Key('clear-library-device')));
    await tester.pumpAndSettle();
    expect(find.text('清空设备词库'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-clear-library-device')));
    await tester.pumpAndSettle();
    expect(provider.clearedTypes, const <String>['device']);
    expect(find.text('词库中还没有内容'), findsOneWidget);
  });

  testWidgets('workspace exposes full JSON import and export actions',
      (tester) async {
    final provider = _TestDictionaryProvider(deviceCount: 1);
    await _pumpManager(tester, provider, width: 700);

    expect(find.byKey(const Key('export-library-json')), findsOneWidget);
    expect(find.byKey(const Key('import-library-json')), findsOneWidget);
    expect(find.text('导出词库 JSON'), findsOneWidget);
    expect(find.text('导入 JSON'), findsOneWidget);
  });
}

Future<void> _pumpManager(
  WidgetTester tester,
  DictionaryProvider provider, {
  required double width,
  double height = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(provider.dispose);
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

class _TestDictionaryProvider extends DictionaryProvider {
  _TestDictionaryProvider({
    required int deviceCount,
    this.failRename = false,
  })  : _devices = List<DictionaryItem>.generate(
          deviceCount,
          (index) => DictionaryItem(
            raw: index == 0
                ? 'Handheld radio'
                : 'Device ${index.toString().padLeft(2, '0')}',
            pinyin: index == 0 ? 'shou tai' : '',
            abbreviation: index == 0 ? 'ST' : '',
            syncId: 'device-$index',
            type: 'device_dictionary',
          ),
        ),
        super(autoload: false);

  final bool failRename;
  final List<DictionaryItem> _devices;
  final List<String> renamedValues = <String>[];
  final List<String> deletedValues = <String>[];
  final List<String> clearedTypes = <String>[];

  @override
  List<DictionaryItem> get deviceDict => _devices;

  @override
  List<DictionaryItem> get antennaDict => <DictionaryItem>[
        DictionaryItem(
          raw: 'Yagi',
          pinyin: '',
          abbreviation: '',
          syncId: 'antenna-0',
          type: 'antenna_dictionary',
        ),
      ];

  @override
  List<DictionaryItem> get callsignDict => const <DictionaryItem>[];

  @override
  List<DictionaryItem> get qthDict => const <DictionaryItem>[];

  @override
  Future<void> renameDevice(String oldRaw, String newRaw) async {
    if (failRename) throw StateError('simulated atomic rename failure');
    final index = _devices.indexWhere((item) => item.raw == oldRaw);
    if (index < 0) throw StateError('source missing');
    renamedValues.add('$oldRaw→$newRaw');
    _devices[index] = _devices[index].copyWith(raw: newRaw);
    notifyListeners();
  }

  @override
  Future<void> deleteDevice(String raw) async {
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
