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
    expect(zh.limitWorkbenchWidthSetting, '限制点名台内容宽度');
    expect(en.limitWorkbenchWidthSetting, 'Limit Net Desk content width');
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
    expect(zh.finishEditing, '结束编辑');
    expect(en.finishEditing, 'Finish editing');
    expect(zh.serverSettingsTitle, '服务器与账户');
    expect(en.serverSettingsTitle, 'Server and account');
    expect(zh.tokenStoragePrivateFileWarning, contains('Linux 用户'));
    expect(en.tokenStoragePrivateFileWarning, contains('private file'));
    expect(zh.tokenStorageMemoryOnlyWarning, contains('退出后需要重新登录'));
    expect(en.tokenStorageMemoryOnlyWarning, contains('after exiting'));
    expect(zh.collaborationConnectionSection, '连接与会话');
    expect(en.collaborationConnectionSection, 'Connection and session');
    expect(zh.logNotOwnedReadOnlyHint, '只能修改或删除自己创建的记录。');
    expect(
      en.logNotOwnedReadOnlyHint,
      'You can change or delete only records that you created.',
    );
    expect(zh.aboutAppTitle, '关于 OpenLogTool');
    expect(zh.aboutAppDescription, contains('点名现场工作流'));
    expect(en.aboutAppTitle, 'About OpenLogTool');
    expect(en.aboutAppDescription, contains('net-control workflows'));
    expect(zh.aboutCheckUpdates, '检查更新');
    expect(en.aboutCheckUpdates, 'Check for updates');
    expect(zh.aboutUpToDate('2.1.0-R'), contains('2.1.0-R'));
    expect(en.aboutUpToDate('2.1.0-R'), contains('up to date'));
    expect(
      zh.aboutUpdateAvailableMessage('2.1.0-R', '2.2.0-R'),
      contains('最新版本：2.2.0-R'),
    );
    expect(
      en.aboutUpdateAvailableMessage('2.1.0-R', '2.2.0-R'),
      contains('Latest version: 2.2.0-R'),
    );
    expect(zh.createEditableLocalCopy, '停止协作并创建本地副本');
    expect(
      zh.createEditableLocalCopyConfirmation('周日晚间点名'),
      contains('原本机协作副本不会被关闭或删除'),
    );
    expect(
      en.createEditableLocalCopy,
      'Stop syncing and create local copy',
    );
    expect(zh.convertCollaborationToLocal, '停止本机协作并转为本地会话');
    expect(
      zh.convertCollaborationToLocalConfirmation('周日晚间点名'),
      contains('服务器上的共享会话、成员和其他设备不受影响'),
    );
    expect(
      en.convertCollaborationToLocal,
      'Stop collaboration on this device and convert to a local session',
    );
  });
}
