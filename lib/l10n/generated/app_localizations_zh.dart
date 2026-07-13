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
  String get historySessionsHint => '查看和切换过去的点名会话；已关闭会话将以只读方式打开。';

  @override
  String get historySessionsEmpty => '暂无历史会话';

  @override
  String historySessionsLoadFailed(String error) {
    return '加载历史会话失败：$error';
  }

  @override
  String get historySessionOpen => '打开会话';

  @override
  String get historySessionCurrent => '当前会话';

  @override
  String historySessionSwitched(String title) {
    return '已打开会话：$title';
  }

  @override
  String historySessionOpenFailed(String error) {
    return '打开会话失败：$error';
  }

  @override
  String get historySessionCloseTitle => '关闭会话';

  @override
  String historySessionCloseConfirmation(String title) {
    return '确定关闭“$title”吗？关闭后仍可在历史会话中只读查看。';
  }

  @override
  String get historySessionClosed => '会话已关闭';

  @override
  String historySessionCloseFailed(String error) {
    return '关闭会话失败：$error';
  }

  @override
  String get historySessionDeleteTitle => '永久删除本机会话';

  @override
  String historySessionDeleteWarning(String title) {
    return '将永久删除本机“$title”的所有日志及本地协作副本。此操作不可撤销，但不会删除或关闭服务器上的共享会话。请输入完整会话名以确认：';
  }

  @override
  String get historySessionDeleteNameLabel => '完整会话名';

  @override
  String get historySessionDeleteAction => '永久删除本机数据';

  @override
  String get historySessionDeleted => '已永久删除本机会话';

  @override
  String historySessionDeleteFailed(String error) {
    return '永久删除本机会话失败：$error';
  }

  @override
  String get historySessionReadOnly => '当前为已关闭的历史会话，只能查看已有记录。';

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
  String get logTimeInvalid => '请输入有效时间（HH:mm）';

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
  String get collaborationScreenTitle => '协作与成员';

  @override
  String get collaborationConnectionSection => '连接与会话';

  @override
  String get collaborationConnectionSectionHint => '查看服务器账号、当前会话和同步入口。';

  @override
  String get collaborationSyncSection => '待处理同步';

  @override
  String get collaborationSyncSectionHint => '复核离线记录，并解决需要人工选择的冲突。';

  @override
  String get collaborationAccessSection => '成员与共享';

  @override
  String get collaborationAccessSectionHint => '管理书记员权限、邀请码和只读公开页面。';

  @override
  String get serverLoggedIn => '已登录';

  @override
  String get serverNotLoggedIn => '尚未登录服务器';

  @override
  String collaborationServerAccount(String url, String id) {
    return '$url\n账号 $id';
  }

  @override
  String get collaborationServerLoginHint => '请先在“设置 → 服务器与账户”中检测服务器并登录。';

  @override
  String get remoteCommitPendingLocalApplyHint =>
      '远端已经提交；客户端只会恢复本地确认，不会重复创建新修改。';

  @override
  String get joinCollaborationTitle => '加入协作';

  @override
  String get joinCollaborationHint => '输入成员邀请码。成功后会以远端相同的 Session ID 安装完整本地副本。';

  @override
  String get inviteCodeLabel => '邀请码';

  @override
  String get join => '加入';

  @override
  String get joinCollaborationSucceeded => '已加入协作会话';

  @override
  String get localCollaborationSessionHint => '本地会话尚未发布。发布时会锁定一致快照并分批上传全部记录。';

  @override
  String collaborationSessionSummary(String state, String role) {
    return '状态 $state · 角色 $role';
  }

  @override
  String collaborationSyncSummary(String transport, int applied, int head) {
    return '同步 $transport · 游标 $applied/$head';
  }

  @override
  String collaborationQueueSummary(int pending, int conflicts, int rejected) {
    return '待同步 $pending · 冲突 $conflicts · 拒绝 $rejected';
  }

  @override
  String get collaborationReliableQueueHint => '本地保存后会进入可靠队列，并由规范事件确认同步。';

  @override
  String collaborationLastSync(String time) {
    return '最近同步 $time';
  }

  @override
  String get collaborationSessionConflictHint =>
      '会话存在未解决冲突。请先在冲突中心处理；重命名、关闭和重新打开暂时不可用。';

  @override
  String get publishSessionSucceeded => '协作会话发布完成';

  @override
  String get publishCollaborationSession => '发布为协作会话';

  @override
  String get retryPublishSession => '重试发布';

  @override
  String get syncNowAndRefreshAccess => '立即同步并刷新权限';

  @override
  String get closeSession => '关闭会话';

  @override
  String get reopenSession => '重新打开';

  @override
  String get transportStopped => '已停止';

  @override
  String get transportConnecting => '连接中';

  @override
  String get transportOnline => '在线';

  @override
  String get transportBackingOff => '等待重连';

  @override
  String get transportAuthRequired => '需要登录';

  @override
  String get transportIncompatible => '协议异常';

  @override
  String get readOnlyRevoked => '成员权限已撤销，本地缓存保持只读。';

  @override
  String get readOnlyClosePending => '关闭请求已保存到本地，等待同步确认；冲突时将保持锁定。';

  @override
  String get readOnlyReopenPending => '重新打开请求已保存到本地，服务器确认前保持只读。';

  @override
  String get readOnlySessionClosed => '协作会话已关闭，本地缓存保持只读。';

  @override
  String get readOnlyViewer => '当前账号是只读成员。';

  @override
  String get readOnlyResyncing => '事件游标需要重装规范快照；待同步修改仍保留。';

  @override
  String get readOnlyCheckingAccess => '正在确认权限与事件游标，暂时保持只读。';

  @override
  String get logNotOwnedReadOnlyHint => '只能修改或删除自己创建的记录。';

  @override
  String get logAuthorUnknownReadOnlyHint => '这条历史记录没有作者信息，普通成员只能查看。';

  @override
  String get logSessionReadOnlyHint => '当前成员角色、会话状态或同步状态不允许修改记录。';

  @override
  String get logConflictReadOnlyHint => '请先在冲突中心解决这条记录。';

  @override
  String get renameCollaborationSession => '重命名协作会话';

  @override
  String get saveLocally => '保存到本地';

  @override
  String get sessionTitleQueued => '标题已保存到本地，等待同步确认';

  @override
  String get closeCollaborationSessionTitle => '关闭协作会话';

  @override
  String get closeCollaborationSessionMessage =>
      '关闭后所有成员都不能继续添加或修改记录；所有者可以稍后重新打开。';

  @override
  String get closeSessionQueued => '会话已在本地关闭，等待同步确认';

  @override
  String get reopenCollaborationSessionTitle => '重新打开协作会话';

  @override
  String get reopenCollaborationSessionMessage =>
      '重新打开会作为一项同步修改提交；服务器确认前仍保持只读。';

  @override
  String get reopenSessionQueued => '重新打开请求已保存到本地，等待同步确认';

  @override
  String get conflictUseRemoteTitle => '采用远端版本';

  @override
  String get conflictKeepLocalTitle => '保留本地版本';

  @override
  String get conflictCopyLocalTitle => '复制为新日志';

  @override
  String get conflictUseRemoteMessage => '本地未同步修改会被远端规范版本替换，此操作不会再次提交修改。';

  @override
  String get conflictKeepLocalMessage => '将基于最新远端版本创建一项新修改。若远端再次变化，仍可能产生新冲突。';

  @override
  String get conflictCopyLocalMessage => '远端原日志会保留，本地内容将使用新的日志 ID 创建副本并重新同步。';

  @override
  String get conflictUseRemoteSucceeded => '已采用远端版本';

  @override
  String get conflictKeepLocalSucceeded => '已保留本地版本并进入重试队列';

  @override
  String get conflictCopyLocalSucceeded => '已复制为新日志并进入同步队列';

  @override
  String get conflictCenterTitle => '冲突中心';

  @override
  String get refreshConflicts => '刷新冲突';

  @override
  String get conflictCenterHint => '可用操作由本地副本按最新权限和实体状态给出；保留或复制会生成新的同步修改。';

  @override
  String get noConflicts => '没有待处理冲突。';

  @override
  String get conflictSession => '会话';

  @override
  String get conflictLog => '日志';

  @override
  String get conflictNoOverlappingFields => '无重叠字段（版本已变化）';

  @override
  String conflictVersionSummary(String fields, int base, int remote) {
    return '字段 $fields · 基线 v$base → 远端 v$remote';
  }

  @override
  String get conflictBase => '基线';

  @override
  String get conflictLocal => '本地';

  @override
  String get conflictRemote => '远端';

  @override
  String get conflictUseRemoteAction => '采用远端';

  @override
  String get conflictKeepLocalAction => '保留本地重试';

  @override
  String get conflictCopyLocalAction => '复制为新日志';

  @override
  String get memberInvitesTitle => '成员邀请';

  @override
  String get roleOwner => '所有者';

  @override
  String get roleEditor => '编辑者';

  @override
  String get roleViewer => '只读成员';

  @override
  String get inviteCreated => '邀请码已生成';

  @override
  String get generate => '生成';

  @override
  String get inviteCodeOneTimeHint => '邀请码只在本次创建响应中显示：';

  @override
  String get noInvites => '暂无邀请';

  @override
  String inviteSummary(int used, int max, String status) {
    return '$used/$max 次 · $status';
  }

  @override
  String inviteExpiresAt(String time) {
    return '有效至 $time';
  }

  @override
  String get inviteRevoked => '已撤销';

  @override
  String get membersTitle => '成员';

  @override
  String get currentAccount => '当前账号';

  @override
  String get memberSetEditor => '成员已设为编辑者';

  @override
  String get memberSetViewer => '成员已设为只读';

  @override
  String get setAsEditor => '设为编辑者';

  @override
  String get setAsViewer => '设为只读成员';

  @override
  String get transferOwnership => '转移所有权';

  @override
  String get removeMember => '移除成员';

  @override
  String transferOwnershipConfirmation(String name) {
    return '转移给 $name 后，你将变为编辑者。';
  }

  @override
  String get ownershipTransferred => '所有权已转移';

  @override
  String removeMemberConfirmation(String name) {
    return '确定移除 $name？权限会立即失效。';
  }

  @override
  String get memberRemoved => '成员已移除';

  @override
  String operationFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get unknown => '未知';

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

  @override
  String get collapseSidebar => '收起侧边栏';

  @override
  String get expandSidebar => '展开侧边栏';

  @override
  String serverConnectionFailed(String detail) {
    return '连接失败：$detail';
  }

  @override
  String serverNetworkError(String url) {
    return '服务器 $url 没有响应。请检查地址和端口，并确认服务端或反向代理正在运行。';
  }

  @override
  String serverNetworkTimeout(String url) {
    return '连接 $url 超时。请检查网络、防火墙和服务端状态。';
  }

  @override
  String serverInvalidResponse(String url) {
    return '已连接 $url，但它没有返回兼容的 OpenLogTool Server 响应。';
  }

  @override
  String get serverAddressRequired => '请先填写服务器地址。';

  @override
  String get serverAddressInvalid => '服务器地址必须是完整的 http(s) URL。';

  @override
  String get serverSettingsTitle => '服务器与账户';

  @override
  String get serverAddressLabel => '服务器地址';

  @override
  String get serverAddressHint => 'http://your-server:3000';

  @override
  String get serverSaveAndCheck => '保存并检测服务器';

  @override
  String serverCheckSucceeded(int min, int max) {
    return '连接成功 · 协议 v$min-$max';
  }

  @override
  String serverInstanceDetails(String instance, String features) {
    return '实例 $instance\n能力 $features';
  }

  @override
  String get serverConnected => '已连接';

  @override
  String get serverNotConnected => '未检测';

  @override
  String get serverSignedOutHint => '登录后可以参与协作，并管理当前账号自己的资料和登录设备。';

  @override
  String get serverLogin => '登录';

  @override
  String get serverRegister => '注册';

  @override
  String get serverLogout => '退出';

  @override
  String serverAccountId(String id) {
    return '账号 ID：$id';
  }

  @override
  String get serverLoginSucceeded => '已登录服务器';

  @override
  String get serverRegistrationSucceeded => '注册并登录成功';

  @override
  String serverLoginFailed(String error) {
    return '登录失败：$error';
  }

  @override
  String serverRegistrationFailed(String error) {
    return '注册失败：$error';
  }

  @override
  String serverLogoutFailed(String error) {
    return '退出失败：$error';
  }

  @override
  String get accountChangeUsername => '修改用户名';

  @override
  String get accountChangePassword => '修改密码';

  @override
  String get accountDeviceSessions => '登录设备';

  @override
  String get accountUsernameUpdated => '用户名已更新';

  @override
  String accountPasswordUpdated(int count) {
    return '密码已更新，已撤销 $count 个登录会话，请重新登录。';
  }

  @override
  String accountUpdateFailed(String error) {
    return '账户操作失败：$error';
  }

  @override
  String get usernameLabel => '用户名';

  @override
  String get usernameLengthHint => '用户名应为 3–64 个字符';

  @override
  String get passwordLabel => '密码';

  @override
  String get fieldRequired => '此项不能为空';

  @override
  String get currentPasswordLabel => '当前密码';

  @override
  String get newPasswordLabel => '新密码';

  @override
  String get confirmNewPasswordLabel => '确认新密码';

  @override
  String get passwordLengthHint => '密码至少需要 10 个字符';

  @override
  String get passwordMismatch => '两次输入的新密码不一致';

  @override
  String get passwordChangeRequiredTitle => '必须修改临时密码';

  @override
  String passwordChangeRequiredHint(String username) {
    return '账号 $username 使用了临时密码。设置新密码后才能继续。';
  }

  @override
  String passwordChangeCredentialExpires(int seconds) {
    return '本次改密凭据将在 $seconds 秒内过期。';
  }

  @override
  String get completePasswordChange => '设置新密码并登录';

  @override
  String get cancelLogin => '取消登录';

  @override
  String get passwordChangeCompleted => '密码已更新并完成登录';

  @override
  String get deviceSessionsTitle => '登录设备';

  @override
  String get deviceSessionsEmpty => '当前没有有效的登录设备';

  @override
  String get deviceUnknown => '未命名设备';

  @override
  String get deviceCurrent => '当前设备';

  @override
  String deviceIp(String ip) {
    return 'IP：$ip';
  }

  @override
  String deviceLastUsed(String time) {
    return '最近使用：$time';
  }

  @override
  String deviceExpires(String time) {
    return '到期：$time';
  }

  @override
  String get revokeDevice => '撤销设备';

  @override
  String get revokeCurrentDevice => '退出当前设备';

  @override
  String get revokeDeviceConfirmation => '撤销后，该设备将不能继续刷新登录状态。';

  @override
  String get revokeCurrentDeviceConfirmation => '退出当前设备后，需要重新输入用户名和密码才能连接服务器。';

  @override
  String get deviceRevoked => '登录设备已撤销';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get excelUseSessionTitleAsHeader => '抬头使用当前会话名';

  @override
  String get excelUseSessionTitleAsHeaderHint =>
      '开启后，Excel 抬头将直接使用当前会话名；会话名为空时继续使用抬头模板。';

  @override
  String get themeColorPickerTitle => '选择主题颜色';

  @override
  String get themeColorPresets => '预设颜色';

  @override
  String get themeColorCustom => '自定义颜色';

  @override
  String get themeColorHex => 'HEX 颜色';

  @override
  String get themeColorHue => '色相';

  @override
  String get themeColorBlue => '蓝色';

  @override
  String get themeColorGreen => '绿色';

  @override
  String get themeColorRed => '红色';

  @override
  String get themeColorOrange => '橙色';

  @override
  String get themeColorPurple => '紫色';

  @override
  String get themeColorPink => '粉色';

  @override
  String get save => '保存';

  @override
  String get add => '添加';

  @override
  String get renameSession => '修改会话名';

  @override
  String get renameSessionTitle => '修改会话名';

  @override
  String get sessionTitleLabel => '会话名';

  @override
  String get renameCollaborationSessionHint => '只有会话所有者可以修改；保存后将同步给其他书记员和主控显示。';

  @override
  String get renameSessionSaved => '会话名已更新';

  @override
  String get renameCollaborationSessionSaved => '会话名已保存，正在同步给其他成员';

  @override
  String renameSessionFailed(String error) {
    return '修改会话名失败：$error';
  }

  @override
  String get renameSessionBlockedClosed => '已关闭的会话不能修改名称';

  @override
  String get renameSessionBlockedBusy => '协作操作进行中，暂时不能修改名称';

  @override
  String get renameSessionBlockedConflict => '请先解决会话冲突，再修改名称';

  @override
  String get renameSessionBlockedNotReady => '协作会话尚未就绪，暂时不能修改名称';

  @override
  String get renameSessionBlockedOwner => '只有会话所有者可以修改名称';

  @override
  String get dictionaryManagementTitle => '词库管理';

  @override
  String get dictionaryManagementHint => '管理点名时可搜索和一键复用的设备、天线、呼号与 QTH 内容。';

  @override
  String get deviceLibrary => '设备词库';

  @override
  String get antennaLibrary => '天线词库';

  @override
  String get callsignLibrary => '呼号词库';

  @override
  String get qthLibrary => 'QTH 词库';

  @override
  String libraryItemCount(int count) {
    return '共 $count 条';
  }

  @override
  String get importLibraryJson => '导入 JSON';

  @override
  String get expandAll => '展开全部';

  @override
  String get collapseAll => '折叠全部';

  @override
  String addLibraryItem(String name) {
    return '添加$name';
  }

  @override
  String searchLibrary(String name) {
    return '搜索$name';
  }

  @override
  String get libraryEmpty => '词库中还没有内容';

  @override
  String get noLibrarySearchResults => '没有匹配的词库内容';

  @override
  String libraryItemAdded(String value) {
    return '已添加：$value';
  }

  @override
  String libraryItemAlreadyExists(String value) {
    return '词库中已有“$value”';
  }

  @override
  String libraryItemAddFailed(String error) {
    return '添加失败：$error';
  }

  @override
  String get libraryImportEmpty => '文件中没有可导入的词库内容';

  @override
  String libraryImportCount(String name, int count) {
    return '$name $count 条';
  }

  @override
  String libraryImportSucceeded(String summary) {
    return '已导入：$summary';
  }

  @override
  String libraryImportFailed(String error) {
    return '导入词库失败：$error';
  }

  @override
  String get listSeparator => '，';

  @override
  String get fontPickerTitle => '选择字体';

  @override
  String get fontSearchHint => '搜索字体';

  @override
  String fontResultCount(int count) {
    return '共 $count 个字体';
  }

  @override
  String get fontSystemDefault => '系统默认';

  @override
  String get fontBuiltIn => '内置';

  @override
  String get fontPreview => '预览';

  @override
  String get fontPreviewSample => 'OpenLogTool · CQ CQ · 点名记录 123';
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
  String get historySessionsHint => '查看和切换过去的点名会话；已关闭会话将以只读方式打开。';

  @override
  String get historySessionsEmpty => '暂无历史会话';

  @override
  String historySessionsLoadFailed(String error) {
    return '加载历史会话失败：$error';
  }

  @override
  String get historySessionOpen => '打开会话';

  @override
  String get historySessionCurrent => '当前会话';

  @override
  String historySessionSwitched(String title) {
    return '已打开会话：$title';
  }

  @override
  String historySessionOpenFailed(String error) {
    return '打开会话失败：$error';
  }

  @override
  String get historySessionCloseTitle => '关闭会话';

  @override
  String historySessionCloseConfirmation(String title) {
    return '确定关闭“$title”吗？关闭后仍可在历史会话中只读查看。';
  }

  @override
  String get historySessionClosed => '会话已关闭';

  @override
  String historySessionCloseFailed(String error) {
    return '关闭会话失败：$error';
  }

  @override
  String get historySessionDeleteTitle => '永久删除本机会话';

  @override
  String historySessionDeleteWarning(String title) {
    return '将永久删除本机“$title”的所有日志及本地协作副本。此操作不可撤销，但不会删除或关闭服务器上的共享会话。请输入完整会话名以确认：';
  }

  @override
  String get historySessionDeleteNameLabel => '完整会话名';

  @override
  String get historySessionDeleteAction => '永久删除本机数据';

  @override
  String get historySessionDeleted => '已永久删除本机会话';

  @override
  String historySessionDeleteFailed(String error) {
    return '永久删除本机会话失败：$error';
  }

  @override
  String get historySessionReadOnly => '当前为已关闭的历史会话，只能查看已有记录。';

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
  String get logTimeInvalid => '请输入有效时间（HH:mm）';

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

  @override
  String get collapseSidebar => '收起侧边栏';

  @override
  String get expandSidebar => '展开侧边栏';

  @override
  String serverConnectionFailed(String detail) {
    return '连接失败：$detail';
  }

  @override
  String serverNetworkError(String url) {
    return '服务器 $url 没有响应。请检查地址和端口，并确认服务端或反向代理正在运行。';
  }

  @override
  String serverNetworkTimeout(String url) {
    return '连接 $url 超时。请检查网络、防火墙和服务端状态。';
  }

  @override
  String serverInvalidResponse(String url) {
    return '已连接 $url，但它没有返回兼容的 OpenLogTool Server 响应。';
  }

  @override
  String get serverAddressRequired => '请先填写服务器地址。';

  @override
  String get serverAddressInvalid => '服务器地址必须是完整的 http(s) URL。';

  @override
  String get serverSettingsTitle => '服务器与账户';

  @override
  String get serverAddressLabel => '服务器地址';

  @override
  String get serverAddressHint => 'http://your-server:3000';

  @override
  String get serverSaveAndCheck => '保存并检测服务器';

  @override
  String serverCheckSucceeded(int min, int max) {
    return '连接成功 · 协议 v$min-$max';
  }

  @override
  String serverInstanceDetails(String instance, String features) {
    return '实例 $instance\n能力 $features';
  }

  @override
  String get serverConnected => '已连接';

  @override
  String get serverNotConnected => '未检测';

  @override
  String get serverSignedOutHint => '登录后可以参与协作，并管理当前账号自己的资料和登录设备。';

  @override
  String get serverLogin => '登录';

  @override
  String get serverRegister => '注册';

  @override
  String get serverLogout => '退出';

  @override
  String serverAccountId(String id) {
    return '账号 ID：$id';
  }

  @override
  String get serverLoginSucceeded => '已登录服务器';

  @override
  String get serverRegistrationSucceeded => '注册并登录成功';

  @override
  String serverLoginFailed(String error) {
    return '登录失败：$error';
  }

  @override
  String serverRegistrationFailed(String error) {
    return '注册失败：$error';
  }

  @override
  String serverLogoutFailed(String error) {
    return '退出失败：$error';
  }

  @override
  String get accountChangeUsername => '修改用户名';

  @override
  String get accountChangePassword => '修改密码';

  @override
  String get accountDeviceSessions => '登录设备';

  @override
  String get accountUsernameUpdated => '用户名已更新';

  @override
  String accountPasswordUpdated(int count) {
    return '密码已更新，已撤销 $count 个登录会话，请重新登录。';
  }

  @override
  String accountUpdateFailed(String error) {
    return '账户操作失败：$error';
  }

  @override
  String get usernameLabel => '用户名';

  @override
  String get usernameLengthHint => '用户名应为 3–64 个字符';

  @override
  String get passwordLabel => '密码';

  @override
  String get fieldRequired => '此项不能为空';

  @override
  String get currentPasswordLabel => '当前密码';

  @override
  String get newPasswordLabel => '新密码';

  @override
  String get confirmNewPasswordLabel => '确认新密码';

  @override
  String get passwordLengthHint => '密码至少需要 10 个字符';

  @override
  String get passwordMismatch => '两次输入的新密码不一致';

  @override
  String get passwordChangeRequiredTitle => '必须修改临时密码';

  @override
  String passwordChangeRequiredHint(String username) {
    return '账号 $username 使用了临时密码。设置新密码后才能继续。';
  }

  @override
  String passwordChangeCredentialExpires(int seconds) {
    return '本次改密凭据将在 $seconds 秒内过期。';
  }

  @override
  String get completePasswordChange => '设置新密码并登录';

  @override
  String get cancelLogin => '取消登录';

  @override
  String get passwordChangeCompleted => '密码已更新并完成登录';

  @override
  String get deviceSessionsTitle => '登录设备';

  @override
  String get deviceSessionsEmpty => '当前没有有效的登录设备';

  @override
  String get deviceUnknown => '未命名设备';

  @override
  String get deviceCurrent => '当前设备';

  @override
  String deviceIp(String ip) {
    return 'IP：$ip';
  }

  @override
  String deviceLastUsed(String time) {
    return '最近使用：$time';
  }

  @override
  String deviceExpires(String time) {
    return '到期：$time';
  }

  @override
  String get revokeDevice => '撤销设备';

  @override
  String get revokeCurrentDevice => '退出当前设备';

  @override
  String get revokeDeviceConfirmation => '撤销后，该设备将不能继续刷新登录状态。';

  @override
  String get revokeCurrentDeviceConfirmation => '退出当前设备后，需要重新输入用户名和密码才能连接服务器。';

  @override
  String get deviceRevoked => '登录设备已撤销';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get excelUseSessionTitleAsHeader => '抬头使用当前会话名';

  @override
  String get excelUseSessionTitleAsHeaderHint =>
      '开启后，Excel 抬头将直接使用当前会话名；会话名为空时继续使用抬头模板。';

  @override
  String get themeColorPickerTitle => '选择主题颜色';

  @override
  String get themeColorPresets => '预设颜色';

  @override
  String get themeColorCustom => '自定义颜色';

  @override
  String get themeColorHex => 'HEX 颜色';

  @override
  String get themeColorHue => '色相';

  @override
  String get themeColorBlue => '蓝色';

  @override
  String get themeColorGreen => '绿色';

  @override
  String get themeColorRed => '红色';

  @override
  String get themeColorOrange => '橙色';

  @override
  String get themeColorPurple => '紫色';

  @override
  String get themeColorPink => '粉色';

  @override
  String get save => '保存';

  @override
  String get add => '添加';

  @override
  String get renameSession => '修改会话名';

  @override
  String get renameSessionTitle => '修改会话名';

  @override
  String get sessionTitleLabel => '会话名';

  @override
  String get renameCollaborationSessionHint => '只有会话所有者可以修改；保存后将同步给其他书记员和主控显示。';

  @override
  String get renameSessionSaved => '会话名已更新';

  @override
  String get renameCollaborationSessionSaved => '会话名已保存，正在同步给其他成员';

  @override
  String renameSessionFailed(String error) {
    return '修改会话名失败：$error';
  }

  @override
  String get renameSessionBlockedClosed => '已关闭的会话不能修改名称';

  @override
  String get renameSessionBlockedBusy => '协作操作进行中，暂时不能修改名称';

  @override
  String get renameSessionBlockedConflict => '请先解决会话冲突，再修改名称';

  @override
  String get renameSessionBlockedNotReady => '协作会话尚未就绪，暂时不能修改名称';

  @override
  String get renameSessionBlockedOwner => '只有会话所有者可以修改名称';

  @override
  String get dictionaryManagementTitle => '词库管理';

  @override
  String get dictionaryManagementHint => '管理点名时可搜索和一键复用的设备、天线、呼号与 QTH 内容。';

  @override
  String get deviceLibrary => '设备词库';

  @override
  String get antennaLibrary => '天线词库';

  @override
  String get callsignLibrary => '呼号词库';

  @override
  String get qthLibrary => 'QTH 词库';

  @override
  String libraryItemCount(int count) {
    return '共 $count 条';
  }

  @override
  String get importLibraryJson => '导入 JSON';

  @override
  String get expandAll => '展开全部';

  @override
  String get collapseAll => '折叠全部';

  @override
  String addLibraryItem(String name) {
    return '添加$name';
  }

  @override
  String searchLibrary(String name) {
    return '搜索$name';
  }

  @override
  String get libraryEmpty => '词库中还没有内容';

  @override
  String get noLibrarySearchResults => '没有匹配的词库内容';

  @override
  String libraryItemAdded(String value) {
    return '已添加：$value';
  }

  @override
  String libraryItemAlreadyExists(String value) {
    return '词库中已有“$value”';
  }

  @override
  String libraryItemAddFailed(String error) {
    return '添加失败：$error';
  }

  @override
  String get libraryImportEmpty => '文件中没有可导入的词库内容';

  @override
  String libraryImportCount(String name, int count) {
    return '$name $count 条';
  }

  @override
  String libraryImportSucceeded(String summary) {
    return '已导入：$summary';
  }

  @override
  String libraryImportFailed(String error) {
    return '导入词库失败：$error';
  }

  @override
  String get listSeparator => '，';

  @override
  String get fontPickerTitle => '选择字体';

  @override
  String get fontSearchHint => '搜索字体';

  @override
  String fontResultCount(int count) {
    return '共 $count 个字体';
  }

  @override
  String get fontSystemDefault => '系统默认';

  @override
  String get fontBuiltIn => '内置';

  @override
  String get fontPreview => '预览';

  @override
  String get fontPreviewSample => 'OpenLogTool · CQ CQ · 点名记录 123';
}
