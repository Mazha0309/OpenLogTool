// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get navWorkbench => '点名台';

  @override
  String get navSessions => '会话';

  @override
  String get navData => '数据';

  @override
  String get navSettings => '设置';

  @override
  String get workbenchNoSession => '尚未开始点名';

  @override
  String get workbenchLocalRecording => '单机记录';

  @override
  String get collaborationLocalOnly => '仅本地';

  @override
  String get collaborationPublishing => '发布中';

  @override
  String get collaborationJoining => '加入中';

  @override
  String get collaborationSnapshotting => '下载快照';

  @override
  String get collaborationCatchingUp => '追赶更新';

  @override
  String get collaborationReady => '已连接';

  @override
  String get collaborationResyncing => '重新同步';

  @override
  String get collaborationRevoked => '权限已撤销';

  @override
  String get collaborationFailed => '同步失败';

  @override
  String collaborationState(String state) {
    return '协作 $state';
  }

  @override
  String pendingSyncCount(int count) {
    return '待同步 $count';
  }

  @override
  String conflictCount(int count) {
    return '冲突 $count';
  }

  @override
  String get localSessionTooltip => '当前为本地会话';

  @override
  String collaborationStatusTooltip(String state, int count) {
    return '协作状态 $state，待同步 $count';
  }

  @override
  String get currentRecord => '当前记录';

  @override
  String currentOrdinal(int ordinal) {
    return '当前第 $ordinal 位';
  }

  @override
  String get sessionsTitle => '会话';

  @override
  String get sessionsSubtitle => '管理本次点名、协作书记员和主控显示设备。';

  @override
  String get noCurrentSession => '当前没有点名会话';

  @override
  String get noCurrentSessionHint => '返回点名台创建会话后即可开始记录。';

  @override
  String get sessionActive => '进行中';

  @override
  String get sessionClosed => '已关闭';

  @override
  String savedPositions(int count) {
    return '$count 位已保存';
  }

  @override
  String get localSession => '本地会话';

  @override
  String get manageCollaboration => '协作与成员';

  @override
  String get enterControllerScreen => '进入主控屏';

  @override
  String get localControllerDisplay => '本机主控显示';

  @override
  String get localControllerDisplayHint => '书记员继续使用主窗口，主控内容在独立只读窗口显示。';

  @override
  String get openFloatingWindow => '打开悬浮窗';

  @override
  String get openSecondDisplayWindow => '打开第二屏窗口';

  @override
  String get historySessions => '历史会话';

  @override
  String get historySessionsHint => '历史记录的切换、关闭与查看暂沿用点名台记录区的“历史记录”入口。';

  @override
  String controllerWindowOpenFailed(String error) {
    return '无法打开主控窗口：$error';
  }

  @override
  String get controllerDisplaySettingsTitle => '主控显示';

  @override
  String get enableControllerDeviceEntry => '启用主控设备入口';

  @override
  String get enableControllerDeviceEntryHint =>
      '开启后可从“会话”进入全屏只读主控屏，适用于安卓平板、手机或独立电脑。';

  @override
  String get defaultInformationDetail => '默认信息详细程度';

  @override
  String get desktopControllerDisplayHint => '本机桌面还可从会话页打开置顶悬浮窗或第二显示器窗口。';

  @override
  String get inAppControllerDisplayHint => '当前设备使用应用内全屏主控模式。';

  @override
  String get controllerScreenTitle => 'OpenLogTool 主控屏';

  @override
  String get controllerFloatingWindowTitle => 'OpenLogTool 主控悬浮窗';

  @override
  String get controllerScreenFallbackTitle => '点名主控屏';

  @override
  String savedPositionCount(int count) {
    return '已保存 $count 位';
  }

  @override
  String get notReceivedDraftUpdate => '尚未收到草稿更新';

  @override
  String updatedAt(String time) {
    return '更新 $time';
  }

  @override
  String editorEditing(String name) {
    return '$name 编辑';
  }

  @override
  String get connectionConnected => '实时连接';

  @override
  String get connectionReconnecting => '正在重连';

  @override
  String get connectionOffline => '连接中断';

  @override
  String get staleControllerDataWarning => '连接已中断，正在显示最后一次收到的内容，数据可能已过期。';

  @override
  String get previousSavedRecord => '上一位已保存记录';

  @override
  String get noPreviousRecord => '暂无上一位记录';

  @override
  String get waitingForCallsign => '等待来台呼号…';

  @override
  String get beingEdited => '正在编辑';

  @override
  String configureControllerDisplay(String detail) {
    return '显示内容（$detail）';
  }

  @override
  String get exitControllerScreen => '退出主控屏';

  @override
  String get controllerDisplayConfiguration => '主控屏显示内容';

  @override
  String get informationDetail => '信息详细程度';

  @override
  String get currentFields => '当前项字段';

  @override
  String get previousFields => '上一位字段';

  @override
  String get cancel => '取消';

  @override
  String get apply => '应用';

  @override
  String get detailMinimal => '极简';

  @override
  String get detailStandard => '标准';

  @override
  String get detailFull => '完整';

  @override
  String get detailCustom => '自定义';

  @override
  String get fieldController => '主控';

  @override
  String get fieldCallsign => '来台呼号';

  @override
  String get fieldTime => '时间';

  @override
  String get fieldRstSent => 'RST 发';

  @override
  String get fieldRstRcvd => 'RST 收';

  @override
  String get fieldQth => 'QTH';

  @override
  String get fieldDevice => '设备';

  @override
  String get fieldPower => '功率';

  @override
  String get fieldAntenna => '天线';

  @override
  String get fieldHeight => '高度';

  @override
  String get fieldRemarks => '备注';

  @override
  String get saveRecord => '保存记录';

  @override
  String get recordAdded => '记录已添加';

  @override
  String get recordQueuedOffline => '网络不可用，记录已保存到本机待复核';

  @override
  String get sharedDraftReadOnly => '当前协作草稿只读';

  @override
  String fieldLockedBy(String name) {
    return '$name 正在编辑';
  }

  @override
  String get offlineReviewTitle => '离线记录待复核';

  @override
  String get resolutionDiscard => '丢弃';

  @override
  String get resolutionSubmitDuplicate => '作为重复记录提交';

  @override
  String get resolutionCopyCurrent => '带入当前草稿';

  @override
  String get callsignRequired => '请输入点名呼号';

  @override
  String get leaveSession => '退出协作会话';

  @override
  String get leaveSessionConfirmation => '退出后本地副本将保持只读；如需再次参与，必须重新获得邀请。';

  @override
  String get confirm => '确认';

  @override
  String get duplicateCallsignWarningSetting => '重复呼号提醒';

  @override
  String get duplicateCallsignWarningHint => '同一场点名中再次录入相同呼号时先提醒，但仍允许保存。';

  @override
  String get duplicateCallsignTitle => '呼号已经记录过';

  @override
  String duplicateCallsignMessage(String callsign) {
    return '$callsign 已在本次点名中记录过，仍要保存吗？';
  }

  @override
  String get saveAnyway => '仍然保存';

  @override
  String get callsignHistoryFillSetting => '呼号历史一键复用';

  @override
  String get callsignHistoryFillHint => '匹配数据库中的既有呼号记录，并可一键带入设备、天线、QTH 等字段。';

  @override
  String get publicShareManagement => '公开主控页面';

  @override
  String get publicShareManagementHint => '仅在服务器同时提供安全公开页面时启用。链接密钥只在创建时显示。';

  @override
  String get createPublicShare => '创建公开链接';

  @override
  String get copyPublicShareLink => '复制链接';

  @override
  String get revokePublicShare => '撤销';

  @override
  String get publicShareLinkCopied => '公开链接已复制';

  @override
  String publicShareExpiresAt(String time) {
    return '有效期至 $time';
  }

  @override
  String get refresh => '刷新';

  @override
  String get reuseDatabaseInformation => '一键复用数据库信息';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get navWorkbench => '点名台';

  @override
  String get navSessions => '会话';

  @override
  String get navData => '数据';

  @override
  String get navSettings => '设置';

  @override
  String get workbenchNoSession => '尚未开始点名';

  @override
  String get workbenchLocalRecording => '单机记录';

  @override
  String get collaborationLocalOnly => '仅本地';

  @override
  String get collaborationPublishing => '发布中';

  @override
  String get collaborationJoining => '加入中';

  @override
  String get collaborationSnapshotting => '下载快照';

  @override
  String get collaborationCatchingUp => '追赶更新';

  @override
  String get collaborationReady => '已连接';

  @override
  String get collaborationResyncing => '重新同步';

  @override
  String get collaborationRevoked => '权限已撤销';

  @override
  String get collaborationFailed => '同步失败';

  @override
  String collaborationState(String state) {
    return '协作 $state';
  }

  @override
  String pendingSyncCount(int count) {
    return '待同步 $count';
  }

  @override
  String conflictCount(int count) {
    return '冲突 $count';
  }

  @override
  String get localSessionTooltip => '当前为本地会话';

  @override
  String collaborationStatusTooltip(String state, int count) {
    return '协作状态 $state，待同步 $count';
  }

  @override
  String get currentRecord => '当前记录';

  @override
  String currentOrdinal(int ordinal) {
    return '当前第 $ordinal 位';
  }

  @override
  String get sessionsTitle => '会话';

  @override
  String get sessionsSubtitle => '管理本次点名、协作书记员和主控显示设备。';

  @override
  String get noCurrentSession => '当前没有点名会话';

  @override
  String get noCurrentSessionHint => '返回点名台创建会话后即可开始记录。';

  @override
  String get sessionActive => '进行中';

  @override
  String get sessionClosed => '已关闭';

  @override
  String savedPositions(int count) {
    return '$count 位已保存';
  }

  @override
  String get localSession => '本地会话';

  @override
  String get manageCollaboration => '协作与成员';

  @override
  String get enterControllerScreen => '进入主控屏';

  @override
  String get localControllerDisplay => '本机主控显示';

  @override
  String get localControllerDisplayHint => '书记员继续使用主窗口，主控内容在独立只读窗口显示。';

  @override
  String get openFloatingWindow => '打开悬浮窗';

  @override
  String get openSecondDisplayWindow => '打开第二屏窗口';

  @override
  String get historySessions => '历史会话';

  @override
  String get historySessionsHint => '历史记录的切换、关闭与查看暂沿用点名台记录区的“历史记录”入口。';

  @override
  String controllerWindowOpenFailed(String error) {
    return '无法打开主控窗口：$error';
  }

  @override
  String get controllerDisplaySettingsTitle => '主控显示';

  @override
  String get enableControllerDeviceEntry => '启用主控设备入口';

  @override
  String get enableControllerDeviceEntryHint =>
      '开启后可从“会话”进入全屏只读主控屏，适用于安卓平板、手机或独立电脑。';

  @override
  String get defaultInformationDetail => '默认信息详细程度';

  @override
  String get desktopControllerDisplayHint => '本机桌面还可从会话页打开置顶悬浮窗或第二显示器窗口。';

  @override
  String get inAppControllerDisplayHint => '当前设备使用应用内全屏主控模式。';

  @override
  String get controllerScreenTitle => 'OpenLogTool 主控屏';

  @override
  String get controllerFloatingWindowTitle => 'OpenLogTool 主控悬浮窗';

  @override
  String get controllerScreenFallbackTitle => '点名主控屏';

  @override
  String savedPositionCount(int count) {
    return '已保存 $count 位';
  }

  @override
  String get notReceivedDraftUpdate => '尚未收到草稿更新';

  @override
  String updatedAt(String time) {
    return '更新 $time';
  }

  @override
  String editorEditing(String name) {
    return '$name 编辑';
  }

  @override
  String get connectionConnected => '实时连接';

  @override
  String get connectionReconnecting => '正在重连';

  @override
  String get connectionOffline => '连接中断';

  @override
  String get staleControllerDataWarning => '连接已中断，正在显示最后一次收到的内容，数据可能已过期。';

  @override
  String get previousSavedRecord => '上一位已保存记录';

  @override
  String get noPreviousRecord => '暂无上一位记录';

  @override
  String get waitingForCallsign => '等待来台呼号…';

  @override
  String get beingEdited => '正在编辑';

  @override
  String configureControllerDisplay(String detail) {
    return '显示内容（$detail）';
  }

  @override
  String get exitControllerScreen => '退出主控屏';

  @override
  String get controllerDisplayConfiguration => '主控屏显示内容';

  @override
  String get informationDetail => '信息详细程度';

  @override
  String get currentFields => '当前项字段';

  @override
  String get previousFields => '上一位字段';

  @override
  String get cancel => '取消';

  @override
  String get apply => '应用';

  @override
  String get detailMinimal => '极简';

  @override
  String get detailStandard => '标准';

  @override
  String get detailFull => '完整';

  @override
  String get detailCustom => '自定义';

  @override
  String get fieldController => '主控';

  @override
  String get fieldCallsign => '来台呼号';

  @override
  String get fieldTime => '时间';

  @override
  String get fieldRstSent => 'RST 发';

  @override
  String get fieldRstRcvd => 'RST 收';

  @override
  String get fieldQth => 'QTH';

  @override
  String get fieldDevice => '设备';

  @override
  String get fieldPower => '功率';

  @override
  String get fieldAntenna => '天线';

  @override
  String get fieldHeight => '高度';

  @override
  String get fieldRemarks => '备注';

  @override
  String get saveRecord => '保存记录';

  @override
  String get recordAdded => '记录已添加';

  @override
  String get recordQueuedOffline => '网络不可用，记录已保存到本机待复核';

  @override
  String get sharedDraftReadOnly => '当前协作草稿只读';

  @override
  String fieldLockedBy(String name) {
    return '$name 正在编辑';
  }

  @override
  String get offlineReviewTitle => '离线记录待复核';

  @override
  String get resolutionDiscard => '丢弃';

  @override
  String get resolutionSubmitDuplicate => '作为重复记录提交';

  @override
  String get resolutionCopyCurrent => '带入当前草稿';

  @override
  String get callsignRequired => '请输入点名呼号';

  @override
  String get leaveSession => '退出协作会话';

  @override
  String get leaveSessionConfirmation => '退出后本地副本将保持只读；如需再次参与，必须重新获得邀请。';

  @override
  String get confirm => '确认';

  @override
  String get duplicateCallsignWarningSetting => '重复呼号提醒';

  @override
  String get duplicateCallsignWarningHint => '同一场点名中再次录入相同呼号时先提醒，但仍允许保存。';

  @override
  String get duplicateCallsignTitle => '呼号已经记录过';

  @override
  String duplicateCallsignMessage(String callsign) {
    return '$callsign 已在本次点名中记录过，仍要保存吗？';
  }

  @override
  String get saveAnyway => '仍然保存';

  @override
  String get callsignHistoryFillSetting => '呼号历史一键复用';

  @override
  String get callsignHistoryFillHint => '匹配数据库中的既有呼号记录，并可一键带入设备、天线、QTH 等字段。';

  @override
  String get publicShareManagement => '公开主控页面';

  @override
  String get publicShareManagementHint => '仅在服务器同时提供安全公开页面时启用。链接密钥只在创建时显示。';

  @override
  String get createPublicShare => '创建公开链接';

  @override
  String get copyPublicShareLink => '复制链接';

  @override
  String get revokePublicShare => '撤销';

  @override
  String get publicShareLinkCopied => '公开链接已复制';

  @override
  String publicShareExpiresAt(String time) {
    return '有效期至 $time';
  }

  @override
  String get refresh => '刷新';

  @override
  String get reuseDatabaseInformation => '一键复用数据库信息';
}
