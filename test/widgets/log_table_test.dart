import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/widgets/log_table.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('keeps RST sent and received aligned with the newest row',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final logs = <LogEntry>[
      _log(
        id: 'old',
        time: 'OLD_TIME',
        report: 'OLD_SENT',
        rstRcvd: 'OLD_RCVD',
      ),
      _log(
        id: 'new',
        time: '20:31',
        report: 'SENT_CELL',
        rstRcvd: 'RCVD_CELL',
      ),
    ];
    final logProvider = _StaticLogProvider(logs);
    final settingsProvider = SettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: logProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settingsProvider,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(height: 400, child: LogTable()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var table = tester.widget<DataTable>(find.byType(DataTable));
    expect(
      table.columns.map((column) => _textOf(tester, column.label)).toList(),
      <String>[
        '#',
        '时间',
        '主控',
        '来台呼号',
        'RST 发',
        'RST 收',
        'QTH',
        '设备',
        '功率',
        '天线',
        '高度',
        '备注',
        '操作',
      ],
    );
    expect(
      table.rows.first.cells
          .map((cell) => _textOf(tester, cell.child))
          .toList(),
      <String>[
        '2',
        '20:31',
        'CTRL_CELL',
        'CALL_CELL',
        'SENT_CELL',
        'RCVD_CELL',
        'QTH_CELL',
        'DEVICE_CELL',
        'POWER_CELL',
        'ANTENNA_CELL',
        'HEIGHT_CELL',
        'REMARKS_CELL',
        '',
      ],
    );
    expect(_textOf(tester, table.rows.last.cells[4].child), 'OLD_SENT');
    expect(_textOf(tester, table.rows.last.cells[5].child), 'OLD_RCVD');

    final actionCell = table.rows.first.cells[12].child;
    final editButton = tester.widget<IconButton>(
      find
          .descendant(
            of: find.byWidget(actionCell),
            matching: find.byType(IconButton),
          )
          .first,
    );
    editButton.onPressed!();
    await tester.pump();

    table = tester.widget<DataTable>(find.byType(DataTable));
    final sentField = _field(tester, table.rows.first.cells[4].child);
    final receivedField = _field(tester, table.rows.first.cells[5].child);
    expect(sentField.controller!.text, 'SENT_CELL');
    expect(receivedField.controller!.text, 'RCVD_CELL');

    sentField.controller!.text = 'SENT_EDITED';
    receivedField.controller!.text = 'RCVD_EDITED';
    final saveButton = tester.widget<IconButton>(
      find
          .descendant(
            of: find.byWidget(table.rows.first.cells[12].child),
            matching: find.byType(IconButton),
          )
          .first,
    );
    saveButton.onPressed!();
    await tester.pumpAndSettle();

    expect(logProvider.updatedIndex, 1);
    expect(
      (logProvider.updatedLog?.report, logProvider.updatedLog?.rstRcvd),
      ('SENT_EDITED', 'RCVD_EDITED'),
    );
  });

  testWidgets('shows a canonical UTC log time in the device timezone',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final localTime = DateTime(2026, 7, 13, 20, 30);
    final logProvider = _StaticLogProvider([
      _log(
        id: 'timezone-log',
        time: localTime.toUtc().toIso8601String(),
        report: '59',
        rstRcvd: '59',
      ),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: logProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: SettingsProvider(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LogTable(readOnly: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(_textOf(tester, table.rows.single.cells[1].child), '20:30');
  });

  testWidgets('default pagination keeps five newest RST records on first page',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final logProvider = _StaticLogProvider(
      List<LogEntry>.generate(
        6,
        (index) => _log(
          id: 'log-${index + 1}',
          time: 'TIME_${index + 1}',
          report: 'SENT_${index + 1}',
          rstRcvd: 'RCVD_${index + 1}',
        ),
      ),
    );
    final settingsProvider = SettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: logProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settingsProvider,
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: LogTable(readOnly: true)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(find.byKey(const Key('log-table-surface')), findsOneWidget);
    expect(find.byKey(const Key('log-pagination')), findsOneWidget);
    final verticalTableScroll = tester
        .widgetList<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(const Key('log-table-surface')),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .singleWhere(
          (scroll) => scroll.scrollDirection == Axis.vertical,
        );
    expect(verticalTableScroll.physics, isA<NeverScrollableScrollPhysics>());
    expect(table.rows, hasLength(5));
    expect(_textOf(tester, table.rows.first.cells[4].child), 'SENT_6');
    expect(_textOf(tester, table.rows.first.cells[5].child), 'RCVD_6');
    expect(_textOf(tester, table.rows.last.cells[4].child), 'SENT_2');
    expect(find.text('SENT_1'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('non-owned collaboration log exposes only a read-only hint',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final logProvider = _StaticLogProvider([
      _log(
        id: 'own-log',
        time: 'OWN_TIME',
        report: '59',
        rstRcvd: '59',
      ),
      _log(
        id: 'other-log',
        time: 'OTHER_TIME',
        report: '59',
        rstRcvd: '59',
      ),
    ]);
    logProvider.setLogMutationGuard(
      (log) => log.id == 'other-log' ? 'COLLABORATION_LOG_NOT_OWNED' : null,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: logProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: SettingsProvider(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(height: 400, child: LogTable()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final table = tester.widget<DataTable>(find.byType(DataTable));
    final otherActions = table.rows.first.cells[12].child;
    expect(
      find.descendant(
        of: find.byWidget(otherActions),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byWidget(otherActions),
        matching: find.byType(Tooltip),
      ),
    );
    expect(
      tooltip.message,
      'You can change or delete only records that you created.',
    );

    final ownActions = table.rows.last.cells[12].child;
    expect(
      find.descendant(
        of: find.byWidget(ownActions),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('runtime locale switch updates table and deletion copy',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final locale = ValueNotifier<Locale>(const Locale('zh', 'CN'));
    addTearDown(locale.dispose);
    final logProvider = _StaticLogProvider([
      _log(
        id: 'localized-log',
        time: '20:31',
        report: '59',
        rstRcvd: '59',
      ),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: logProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: SettingsProvider(),
          ),
          ChangeNotifierProvider<SnackbarLogProvider>(
            create: (_) => SnackbarLogProvider(),
          ),
        ],
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, currentLocale, child) => MaterialApp(
            locale: currentLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SizedBox(height: 400, child: LogTable()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主控'), findsOneWidget);
    expect(find.byTooltip('编辑记录'), findsOneWidget);

    locale.value = const Locale('en', 'US');
    await tester.pumpAndSettle();

    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(
      table.columns.map((column) => _textOf(tester, column.label)).toList(),
      <String>[
        '#',
        'Time',
        'Controller',
        'Callsign',
        'RST sent',
        'RST received',
        'QTH',
        'Radio',
        'Power',
        'Antenna',
        'Height',
        'Remarks',
        'Actions',
      ],
    );
    expect(find.byTooltip('Edit record'), findsOneWidget);
    expect(find.byTooltip('Delete record'), findsOneWidget);
    expect(find.text('主控'), findsNothing);

    _openDeleteDialog(tester);
    await tester.pumpAndSettle();
    expect(find.text('Delete record'), findsOneWidget);
    expect(find.text('Delete this record?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Delete'), findsOneWidget);

    tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Delete'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Record deleted'), findsOneWidget);
  });

  testWidgets('en_US localizes the empty table state', (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );

    await _pumpLogTable(
      tester,
      _StaticLogProvider([]),
      locale: const Locale('en', 'US'),
    );

    expect(find.text('No saved records'), findsOneWidget);
    expect(
      find.text('Add the first record using the form above.'),
      findsOneWidget,
    );
    expect(find.text('暂无已保存记录'), findsNothing);
  });

  testWidgets('failed save keeps editing controls and the entered value',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final logProvider = _StaticLogProvider([
      _log(
        id: 'save-failure',
        time: '20:31',
        report: '59',
        rstRcvd: '59',
      ),
    ])
      ..updateError = StateError('write failed');

    await _pumpLogTable(tester, logProvider);

    var table = tester.widget<DataTable>(find.byType(DataTable));
    final editButton = tester.widget<IconButton>(
      find
          .descendant(
            of: find.byWidget(table.rows.single.cells[12].child),
            matching: find.byType(IconButton),
          )
          .first,
    );
    editButton.onPressed!();
    await tester.pump();

    table = tester.widget<DataTable>(find.byType(DataTable));
    _field(tester, table.rows.single.cells[3].child).controller!.text =
        'USER_EDIT';
    final saveButton = tester.widget<IconButton>(
      find
          .descendant(
            of: find.byWidget(table.rows.single.cells[12].child),
            matching: find.byType(IconButton),
          )
          .first,
    );
    saveButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(logProvider.updateCalls, 1);
    expect(
      _field(tester, table.rows.single.cells[3].child).controller!.text,
      'USER_EDIT',
    );
    expect(find.byTooltip('保存'), findsOneWidget);
    expect(find.text('操作失败：Bad state: write failed'), findsOneWidget);
  });

  testWidgets('delete awaits completion and ignores repeated confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final deletion = Completer<void>();
    final logProvider = _StaticLogProvider([
      _log(
        id: 'delete-pending',
        time: '20:31',
        report: '59',
        rstRcvd: '59',
      ),
    ])
      ..deleteGate = deletion;

    await _pumpLogTable(tester, logProvider);
    _openDeleteDialog(tester);
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '删除'),
    );
    confirmButton.onPressed!();
    confirmButton.onPressed!();
    await tester.pump();

    expect(logProvider.deleteCalls, 1);
    expect(find.text('删除记录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('记录已删除'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    deletion.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('删除记录'), findsNothing);
    expect(find.text('记录已删除'), findsOneWidget);
    expect(logProvider.logs, isEmpty);
  });

  testWidgets('failed delete keeps the record and dialog available to retry',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': false},
    );
    final logProvider = _StaticLogProvider([
      _log(
        id: 'delete-failure',
        time: '20:31',
        report: '59',
        rstRcvd: '59',
      ),
    ])
      ..deleteError = StateError('delete failed');

    await _pumpLogTable(tester, logProvider);
    _openDeleteDialog(tester);
    await tester.pumpAndSettle();

    tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, '删除'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(logProvider.deleteCalls, 1);
    expect(logProvider.logs.single.id, 'delete-failure');
    expect(find.text('删除记录'), findsOneWidget);
    expect(find.text('记录已删除'), findsNothing);
    expect(find.text('操作失败：Bad state: delete failed'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '删除'),
          )
          .onPressed,
      isNotNull,
    );
  });
}

Future<void> _pumpLogTable(
  WidgetTester tester,
  LogProvider logProvider, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logProvider),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: SettingsProvider(),
        ),
        ChangeNotifierProvider<SnackbarLogProvider>(
          create: (_) => SnackbarLogProvider(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(height: 400, child: LogTable()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _openDeleteDialog(WidgetTester tester) {
  final table = tester.widget<DataTable>(find.byType(DataTable));
  final deleteButton = tester
      .widgetList<IconButton>(
        find.descendant(
          of: find.byWidget(table.rows.single.cells[12].child),
          matching: find.byType(IconButton),
        ),
      )
      .last;
  deleteButton.onPressed!();
}

String _textOf(WidgetTester tester, Widget root) => tester
    .widgetList<Text>(
      find.descendant(of: find.byWidget(root), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join();

TextField _field(WidgetTester tester, Widget root) => tester.widget<TextField>(
      find.descendant(
        of: find.byWidget(root),
        matching: find.byType(TextField),
      ),
    );

LogEntry _log({
  required String id,
  required String time,
  required String report,
  required String rstRcvd,
}) =>
    LogEntry(
      id: id,
      time: time,
      controller: 'CTRL_CELL',
      callsign: 'CALL_CELL',
      report: report,
      rstRcvd: rstRcvd,
      qth: 'QTH_CELL',
      device: 'DEVICE_CELL',
      power: 'POWER_CELL',
      antenna: 'ANTENNA_CELL',
      height: 'HEIGHT_CELL',
      remarks: 'REMARKS_CELL',
    );

class _StaticLogProvider extends LogProvider {
  _StaticLogProvider(this.initialLogs);

  final List<LogEntry> initialLogs;
  int? updatedIndex;
  LogEntry? updatedLog;
  Object? updateError;
  int updateCalls = 0;
  Completer<void>? deleteGate;
  Object? deleteError;
  int deleteCalls = 0;

  @override
  List<LogEntry> get logs => initialLogs;

  @override
  Future<void> updateLog(int index, LogEntry log) async {
    updateCalls += 1;
    final error = updateError;
    if (error != null) throw error;
    updatedIndex = index;
    updatedLog = log;
  }

  @override
  Future<void> deleteLogById(String syncId) async {
    deleteCalls += 1;
    await deleteGate?.future;
    final error = deleteError;
    if (error != null) throw error;
    initialLogs.removeWhere((log) => log.id == syncId);
    notifyListeners();
  }
}
