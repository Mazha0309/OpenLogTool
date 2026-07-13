import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';

void main() {
  test('uses zh_CN by default and maps English variants to en_US', () {
    expect(
      resolveAppLocale(
        const Locale('ja', 'JP'),
        AppLocalizations.supportedLocales,
      ),
      const Locale('zh', 'CN'),
    );
    expect(
      resolveAppLocale(
        const Locale('en', 'GB'),
        AppLocalizations.supportedLocales,
      ),
      const Locale('en', 'US'),
    );
  });

  test('zh_CN and en_US include the four primary destinations', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh', 'CN'));
    final en = await AppLocalizations.delegate.load(const Locale('en', 'US'));

    expect(
      [zh.navWorkbench, zh.navSessions, zh.navData, zh.navSettings],
      ['点名台', '会话', '数据', '设置'],
    );
    expect(
      [en.navWorkbench, en.navSessions, en.navData, en.navSettings],
      ['Net Desk', 'Sessions', 'Data', 'Settings'],
    );
    expect(collaborationStateLabel(zh, 'ready'), '已连接');
    expect(collaborationStateLabel(en, 'ready'), 'Connected');
    expect(zh.callsignHistoryFillSetting, '呼号历史一键复用');
    expect(en.callsignHistoryFillSetting, 'Reuse callsign history');
    expect(zh.historySessions, '历史会话');
    expect(zh.historySessionsHint, isNot(contains('历史记录')));
    expect(en.historySessionOpen, 'Open session');
    expect(zh.logTimeInvalid, '请输入有效时间（HH:mm）');
    expect(en.logTimeInvalid, 'Enter a valid time (HH:mm)');
    expect(zh.offlineReviewTitle, '离线记录待复核');
    expect(en.offlineReviewTitle, 'Offline records need review');
    expect(zh.collapseSidebar, '收起侧边栏');
    expect(zh.expandSidebar, '展开侧边栏');
    expect(en.collapseSidebar, 'Collapse sidebar');
    expect(en.expandSidebar, 'Expand sidebar');
    expect(zh.serverSettingsTitle, '服务器与账户');
    expect(en.serverSettingsTitle, 'Server and account');
    expect(zh.collaborationConnectionSection, '连接与会话');
    expect(en.collaborationConnectionSection, 'Connection and session');
    expect(zh.logNotOwnedReadOnlyHint, '只能修改或删除自己创建的记录。');
    expect(
      en.logNotOwnedReadOnlyHint,
      'You can change or delete only records that you created.',
    );
  });
}
