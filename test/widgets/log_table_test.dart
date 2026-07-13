import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
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
        time: 'NEW_TIME',
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
        '点名主控',
        '呼号',
        'RST发',
        'RST收',
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
        'NEW_TIME',
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

  testWidgets('pagination keeps the newest RST records on the first page',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'paginationEnabled': true},
    );
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
    await settingsProvider.setPaginationEnabled(true);

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

  @override
  List<LogEntry> get logs => initialLogs;

  @override
  Future<void> updateLog(int index, LogEntry log) async {
    updatedIndex = index;
    updatedLog = log;
  }
}
