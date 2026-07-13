import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/screens/controller_display_screen.dart';
import 'package:openlogtool/utils/log_time.dart';

void main() {
  testWidgets('shows current, previous and collaboration status',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ControllerDisplayScreen(
          data: _data(),
          showCloseButton: false,
        ),
      ),
    );

    expect(find.text('周日晚间点名'), findsOneWidget);
    expect(find.text('当前第 8 位'), findsOneWidget);
    expect(find.text('已保存 7 位 · 更新 20:00:00 · 书记员乙 编辑'), findsOneWidget);
    expect(find.text('BA4AAA'), findsWidgets);
    expect(find.text('上一位已保存记录'), findsOneWidget);
    expect(find.text('BH4BBB'), findsOneWidget);
    expect(find.text('书记员甲'), findsOneWidget);
    expect(find.byKey(const Key('controller-stale-banner')), findsNothing);
    expect(
      find.byKey(const Key('controller-landscape-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('adapts to a phone and warns when data is stale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ControllerDisplayScreen(
          data: _data(connectionState: ControllerConnectionState.offline),
          preferences: const ControllerDisplayPreferences(
            detail: ControllerDisplayDetail.minimal,
          ),
          showCloseButton: false,
        ),
      ),
    );

    expect(find.byKey(const Key('controller-stale-banner')), findsOneWidget);
    expect(find.textContaining('数据可能已过期'), findsOneWidget);
    expect(find.byKey(const Key('controller-field-controller')), findsWidgets);
    expect(find.byKey(const Key('controller-field-qth')), findsNothing);
    expect(
      find.byKey(const Key('controller-portrait-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('controller-compact-header')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'full-detail portrait layout scrolls and formats a raw ISO timestamp',
      (tester) async {
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rawTimestamp = '2026-07-13T12:15:00Z';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ControllerDisplayScreen(
          data: _data(currentTime: rawTimestamp),
          showCloseButton: false,
        ),
      ),
    );

    expect(
      find.byKey(const Key('controller-portrait-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('controller-field-remarks')),
      findsNWidgets(2),
    );
    expect(find.text(rawTimestamp), findsNothing);
    expect(
      find.text(formatLogTimeForDisplay(rawTimestamp)),
      findsOneWidget,
    );
    expect(find.text('20:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies a changed detail preset', (tester) async {
    ControllerDisplayPreferences? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ControllerDisplayScreen(
          data: _data(),
          onPreferencesChanged: (value) => changed = value,
          showCloseButton: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('configure-controller-display')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('controller-detail-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('极简').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('save-controller-display-settings')),
    );
    await tester.pumpAndSettle();

    expect(changed?.detail, ControllerDisplayDetail.minimal);
    expect(find.byKey(const Key('controller-field-qth')), findsNothing);
  });

  testWidgets('renders the controller display in en_US', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ControllerDisplayScreen(
          data: _data(connectionState: ControllerConnectionState.offline),
          preferences: const ControllerDisplayPreferences(
            detail: ControllerDisplayDetail.minimal,
          ),
          showCloseButton: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current #8'), findsOneWidget);
    expect(find.text('Previous saved record'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.textContaining('may be out of date'), findsOneWidget);
    expect(find.text('Controller'), findsWidgets);
  });
}

ControllerDisplayDto _data({
  ControllerConnectionState connectionState =
      ControllerConnectionState.connected,
  String currentTime = '20:15',
  String previousTime = '20:12',
}) =>
    ControllerDisplayDto(
      sessionTitle: '周日晚间点名',
      currentOrdinal: 8,
      totalRecords: 7,
      current: ControllerRecordDisplay(
        controller: 'BG5CRL',
        callsign: 'BA4AAA',
        time: currentTime,
        rstSent: '59',
        rstRcvd: '57',
        qth: '上海',
        device: 'IC-7300',
        power: '100W',
        antenna: 'DP',
        height: '12m',
        remarks: '移动设台',
      ),
      previous: ControllerRecordDisplay(
        controller: 'BG5CRL',
        callsign: 'BH4BBB',
        time: previousTime,
        rstSent: '59',
        rstRcvd: '59',
        qth: '苏州',
        device: 'FT-991A',
        power: '50W',
        antenna: 'GP',
        height: '20m',
        remarks: '固定台',
      ),
      connectionState: connectionState,
      lastUpdatedBy: '书记员乙',
      lastUpdatedAt: DateTime.utc(2026, 7, 13, 12),
      locks: const [
        ControllerFieldLock(field: 'qth', holderName: '书记员甲'),
      ],
    );
