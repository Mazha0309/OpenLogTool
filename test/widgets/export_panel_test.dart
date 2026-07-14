import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/export_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Excel configuration summary and editor fit a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsProvider();
    final sessions = SessionProvider();
    addTearDown(settings.dispose);
    addTearDown(sessions.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ExportPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excel 配置概览'), findsOneWidget);
    expect(find.text('编辑设置'), findsOneWidget);
    expect(
      find.text('这里展示当前配置；交替行可直接切换，其他选项请点击“编辑设置”。'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('编辑设置'));
    await tester.tap(find.text('编辑设置'));
    await tester.pumpAndSettle();

    expect(find.text('编辑 Excel 导出设置'), findsOneWidget);
    expect(find.text('表格样式'), findsOneWidget);
    expect(find.text('模板变量'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
