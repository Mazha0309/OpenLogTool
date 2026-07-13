import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en'),
    Locale('en', 'US'),
    Locale('zh')
  ];

  /// No description provided for @navWorkbench.
  ///
  /// In zh, this message translates to:
  /// **'点名台'**
  String get navWorkbench;

  /// No description provided for @navSessions.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get navSessions;

  /// No description provided for @navData.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get navData;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @workbenchNoSession.
  ///
  /// In zh, this message translates to:
  /// **'尚未开始点名'**
  String get workbenchNoSession;

  /// No description provided for @workbenchLocalRecording.
  ///
  /// In zh, this message translates to:
  /// **'单机记录'**
  String get workbenchLocalRecording;

  /// No description provided for @collaborationLocalOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅本地'**
  String get collaborationLocalOnly;

  /// No description provided for @collaborationPublishing.
  ///
  /// In zh, this message translates to:
  /// **'发布中'**
  String get collaborationPublishing;

  /// No description provided for @collaborationJoining.
  ///
  /// In zh, this message translates to:
  /// **'加入中'**
  String get collaborationJoining;

  /// No description provided for @collaborationSnapshotting.
  ///
  /// In zh, this message translates to:
  /// **'下载快照'**
  String get collaborationSnapshotting;

  /// No description provided for @collaborationCatchingUp.
  ///
  /// In zh, this message translates to:
  /// **'追赶更新'**
  String get collaborationCatchingUp;

  /// No description provided for @collaborationReady.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get collaborationReady;

  /// No description provided for @collaborationResyncing.
  ///
  /// In zh, this message translates to:
  /// **'重新同步'**
  String get collaborationResyncing;

  /// No description provided for @collaborationRevoked.
  ///
  /// In zh, this message translates to:
  /// **'权限已撤销'**
  String get collaborationRevoked;

  /// No description provided for @collaborationFailed.
  ///
  /// In zh, this message translates to:
  /// **'同步失败'**
  String get collaborationFailed;

  /// No description provided for @collaborationState.
  ///
  /// In zh, this message translates to:
  /// **'协作 {state}'**
  String collaborationState(String state);

  /// No description provided for @pendingSyncCount.
  ///
  /// In zh, this message translates to:
  /// **'待同步 {count}'**
  String pendingSyncCount(int count);

  /// No description provided for @conflictCount.
  ///
  /// In zh, this message translates to:
  /// **'冲突 {count}'**
  String conflictCount(int count);

  /// No description provided for @localSessionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'当前为本地会话'**
  String get localSessionTooltip;

  /// No description provided for @collaborationStatusTooltip.
  ///
  /// In zh, this message translates to:
  /// **'协作状态 {state}，待同步 {count}'**
  String collaborationStatusTooltip(String state, int count);

  /// No description provided for @currentRecord.
  ///
  /// In zh, this message translates to:
  /// **'当前记录'**
  String get currentRecord;

  /// No description provided for @currentOrdinal.
  ///
  /// In zh, this message translates to:
  /// **'当前第 {ordinal} 位'**
  String currentOrdinal(int ordinal);

  /// No description provided for @sessionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get sessionsTitle;

  /// No description provided for @sessionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理本次点名、协作书记员和主控显示设备。'**
  String get sessionsSubtitle;

  /// No description provided for @noCurrentSession.
  ///
  /// In zh, this message translates to:
  /// **'当前没有点名会话'**
  String get noCurrentSession;

  /// No description provided for @noCurrentSessionHint.
  ///
  /// In zh, this message translates to:
  /// **'返回点名台创建会话后即可开始记录。'**
  String get noCurrentSessionHint;

  /// No description provided for @sessionActive.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get sessionActive;

  /// No description provided for @sessionClosed.
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get sessionClosed;

  /// No description provided for @savedPositions.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位已保存'**
  String savedPositions(int count);

  /// No description provided for @localSession.
  ///
  /// In zh, this message translates to:
  /// **'本地会话'**
  String get localSession;

  /// No description provided for @manageCollaboration.
  ///
  /// In zh, this message translates to:
  /// **'协作与成员'**
  String get manageCollaboration;

  /// No description provided for @enterControllerScreen.
  ///
  /// In zh, this message translates to:
  /// **'进入主控屏'**
  String get enterControllerScreen;

  /// No description provided for @localControllerDisplay.
  ///
  /// In zh, this message translates to:
  /// **'本机主控显示'**
  String get localControllerDisplay;

  /// No description provided for @localControllerDisplayHint.
  ///
  /// In zh, this message translates to:
  /// **'书记员继续使用主窗口，主控内容在独立只读窗口显示。'**
  String get localControllerDisplayHint;

  /// No description provided for @openFloatingWindow.
  ///
  /// In zh, this message translates to:
  /// **'打开悬浮窗'**
  String get openFloatingWindow;

  /// No description provided for @openSecondDisplayWindow.
  ///
  /// In zh, this message translates to:
  /// **'打开第二屏窗口'**
  String get openSecondDisplayWindow;

  /// No description provided for @historySessions.
  ///
  /// In zh, this message translates to:
  /// **'历史会话'**
  String get historySessions;

  /// No description provided for @historySessionsHint.
  ///
  /// In zh, this message translates to:
  /// **'历史记录的切换、关闭与查看暂沿用点名台记录区的“历史记录”入口。'**
  String get historySessionsHint;

  /// No description provided for @controllerWindowOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开主控窗口：{error}'**
  String controllerWindowOpenFailed(String error);

  /// No description provided for @controllerDisplaySettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'主控显示'**
  String get controllerDisplaySettingsTitle;

  /// No description provided for @enableControllerDeviceEntry.
  ///
  /// In zh, this message translates to:
  /// **'启用主控设备入口'**
  String get enableControllerDeviceEntry;

  /// No description provided for @enableControllerDeviceEntryHint.
  ///
  /// In zh, this message translates to:
  /// **'开启后可从“会话”进入全屏只读主控屏，适用于安卓平板、手机或独立电脑。'**
  String get enableControllerDeviceEntryHint;

  /// No description provided for @defaultInformationDetail.
  ///
  /// In zh, this message translates to:
  /// **'默认信息详细程度'**
  String get defaultInformationDetail;

  /// No description provided for @desktopControllerDisplayHint.
  ///
  /// In zh, this message translates to:
  /// **'本机桌面还可从会话页打开置顶悬浮窗或第二显示器窗口。'**
  String get desktopControllerDisplayHint;

  /// No description provided for @inAppControllerDisplayHint.
  ///
  /// In zh, this message translates to:
  /// **'当前设备使用应用内全屏主控模式。'**
  String get inAppControllerDisplayHint;

  /// No description provided for @controllerScreenTitle.
  ///
  /// In zh, this message translates to:
  /// **'OpenLogTool 主控屏'**
  String get controllerScreenTitle;

  /// No description provided for @controllerFloatingWindowTitle.
  ///
  /// In zh, this message translates to:
  /// **'OpenLogTool 主控悬浮窗'**
  String get controllerFloatingWindowTitle;

  /// No description provided for @controllerScreenFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'点名主控屏'**
  String get controllerScreenFallbackTitle;

  /// No description provided for @savedPositionCount.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 位'**
  String savedPositionCount(int count);

  /// No description provided for @notReceivedDraftUpdate.
  ///
  /// In zh, this message translates to:
  /// **'尚未收到草稿更新'**
  String get notReceivedDraftUpdate;

  /// No description provided for @updatedAt.
  ///
  /// In zh, this message translates to:
  /// **'更新 {time}'**
  String updatedAt(String time);

  /// No description provided for @editorEditing.
  ///
  /// In zh, this message translates to:
  /// **'{name} 编辑'**
  String editorEditing(String name);

  /// No description provided for @connectionConnected.
  ///
  /// In zh, this message translates to:
  /// **'实时连接'**
  String get connectionConnected;

  /// No description provided for @connectionReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在重连'**
  String get connectionReconnecting;

  /// No description provided for @connectionOffline.
  ///
  /// In zh, this message translates to:
  /// **'连接中断'**
  String get connectionOffline;

  /// No description provided for @staleControllerDataWarning.
  ///
  /// In zh, this message translates to:
  /// **'连接已中断，正在显示最后一次收到的内容，数据可能已过期。'**
  String get staleControllerDataWarning;

  /// No description provided for @previousSavedRecord.
  ///
  /// In zh, this message translates to:
  /// **'上一位已保存记录'**
  String get previousSavedRecord;

  /// No description provided for @noPreviousRecord.
  ///
  /// In zh, this message translates to:
  /// **'暂无上一位记录'**
  String get noPreviousRecord;

  /// No description provided for @waitingForCallsign.
  ///
  /// In zh, this message translates to:
  /// **'等待来台呼号…'**
  String get waitingForCallsign;

  /// No description provided for @beingEdited.
  ///
  /// In zh, this message translates to:
  /// **'正在编辑'**
  String get beingEdited;

  /// No description provided for @configureControllerDisplay.
  ///
  /// In zh, this message translates to:
  /// **'显示内容（{detail}）'**
  String configureControllerDisplay(String detail);

  /// No description provided for @exitControllerScreen.
  ///
  /// In zh, this message translates to:
  /// **'退出主控屏'**
  String get exitControllerScreen;

  /// No description provided for @controllerDisplayConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'主控屏显示内容'**
  String get controllerDisplayConfiguration;

  /// No description provided for @informationDetail.
  ///
  /// In zh, this message translates to:
  /// **'信息详细程度'**
  String get informationDetail;

  /// No description provided for @currentFields.
  ///
  /// In zh, this message translates to:
  /// **'当前项字段'**
  String get currentFields;

  /// No description provided for @previousFields.
  ///
  /// In zh, this message translates to:
  /// **'上一位字段'**
  String get previousFields;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @apply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get apply;

  /// No description provided for @detailMinimal.
  ///
  /// In zh, this message translates to:
  /// **'极简'**
  String get detailMinimal;

  /// No description provided for @detailStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get detailStandard;

  /// No description provided for @detailFull.
  ///
  /// In zh, this message translates to:
  /// **'完整'**
  String get detailFull;

  /// No description provided for @detailCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get detailCustom;

  /// No description provided for @fieldController.
  ///
  /// In zh, this message translates to:
  /// **'主控'**
  String get fieldController;

  /// No description provided for @fieldCallsign.
  ///
  /// In zh, this message translates to:
  /// **'来台呼号'**
  String get fieldCallsign;

  /// No description provided for @fieldTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get fieldTime;

  /// No description provided for @fieldRstSent.
  ///
  /// In zh, this message translates to:
  /// **'RST 发'**
  String get fieldRstSent;

  /// No description provided for @fieldRstRcvd.
  ///
  /// In zh, this message translates to:
  /// **'RST 收'**
  String get fieldRstRcvd;

  /// No description provided for @fieldQth.
  ///
  /// In zh, this message translates to:
  /// **'QTH'**
  String get fieldQth;

  /// No description provided for @fieldDevice.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get fieldDevice;

  /// No description provided for @fieldPower.
  ///
  /// In zh, this message translates to:
  /// **'功率'**
  String get fieldPower;

  /// No description provided for @fieldAntenna.
  ///
  /// In zh, this message translates to:
  /// **'天线'**
  String get fieldAntenna;

  /// No description provided for @fieldHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get fieldHeight;

  /// No description provided for @fieldRemarks.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get fieldRemarks;

  /// No description provided for @saveRecord.
  ///
  /// In zh, this message translates to:
  /// **'保存记录'**
  String get saveRecord;

  /// No description provided for @recordAdded.
  ///
  /// In zh, this message translates to:
  /// **'记录已添加'**
  String get recordAdded;

  /// No description provided for @recordQueuedOffline.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，记录已保存到本机待复核'**
  String get recordQueuedOffline;

  /// No description provided for @sharedDraftReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'当前协作草稿只读'**
  String get sharedDraftReadOnly;

  /// No description provided for @fieldLockedBy.
  ///
  /// In zh, this message translates to:
  /// **'{name} 正在编辑'**
  String fieldLockedBy(String name);

  /// No description provided for @offlineReviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'离线记录待复核'**
  String get offlineReviewTitle;

  /// No description provided for @resolutionDiscard.
  ///
  /// In zh, this message translates to:
  /// **'丢弃'**
  String get resolutionDiscard;

  /// No description provided for @resolutionSubmitDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'作为重复记录提交'**
  String get resolutionSubmitDuplicate;

  /// No description provided for @resolutionCopyCurrent.
  ///
  /// In zh, this message translates to:
  /// **'带入当前草稿'**
  String get resolutionCopyCurrent;

  /// No description provided for @callsignRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入点名呼号'**
  String get callsignRequired;

  /// No description provided for @leaveSession.
  ///
  /// In zh, this message translates to:
  /// **'退出协作会话'**
  String get leaveSession;

  /// No description provided for @leaveSessionConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'退出后本地副本将保持只读；如需再次参与，必须重新获得邀请。'**
  String get leaveSessionConfirmation;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @duplicateCallsignWarningSetting.
  ///
  /// In zh, this message translates to:
  /// **'重复呼号提醒'**
  String get duplicateCallsignWarningSetting;

  /// No description provided for @duplicateCallsignWarningHint.
  ///
  /// In zh, this message translates to:
  /// **'同一场点名中再次录入相同呼号时先提醒，但仍允许保存。'**
  String get duplicateCallsignWarningHint;

  /// No description provided for @duplicateCallsignTitle.
  ///
  /// In zh, this message translates to:
  /// **'呼号已经记录过'**
  String get duplicateCallsignTitle;

  /// No description provided for @duplicateCallsignMessage.
  ///
  /// In zh, this message translates to:
  /// **'{callsign} 已在本次点名中记录过，仍要保存吗？'**
  String duplicateCallsignMessage(String callsign);

  /// No description provided for @saveAnyway.
  ///
  /// In zh, this message translates to:
  /// **'仍然保存'**
  String get saveAnyway;

  /// No description provided for @callsignHistoryFillSetting.
  ///
  /// In zh, this message translates to:
  /// **'呼号历史一键复用'**
  String get callsignHistoryFillSetting;

  /// No description provided for @callsignHistoryFillHint.
  ///
  /// In zh, this message translates to:
  /// **'匹配数据库中的既有呼号记录，并可一键带入设备、天线、QTH 等字段。'**
  String get callsignHistoryFillHint;

  /// No description provided for @publicShareManagement.
  ///
  /// In zh, this message translates to:
  /// **'公开主控页面'**
  String get publicShareManagement;

  /// No description provided for @publicShareManagementHint.
  ///
  /// In zh, this message translates to:
  /// **'仅在服务器同时提供安全公开页面时启用。链接密钥只在创建时显示。'**
  String get publicShareManagementHint;

  /// No description provided for @createPublicShare.
  ///
  /// In zh, this message translates to:
  /// **'创建公开链接'**
  String get createPublicShare;

  /// No description provided for @copyPublicShareLink.
  ///
  /// In zh, this message translates to:
  /// **'复制链接'**
  String get copyPublicShareLink;

  /// No description provided for @revokePublicShare.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get revokePublicShare;

  /// No description provided for @publicShareLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'公开链接已复制'**
  String get publicShareLinkCopied;

  /// No description provided for @publicShareExpiresAt.
  ///
  /// In zh, this message translates to:
  /// **'有效期至 {time}'**
  String publicShareExpiresAt(String time);

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @reuseDatabaseInformation.
  ///
  /// In zh, this message translates to:
  /// **'一键复用数据库信息'**
  String get reuseDatabaseInformation;

  /// No description provided for @collapseSidebar.
  ///
  /// In zh, this message translates to:
  /// **'收起侧边栏'**
  String get collapseSidebar;

  /// No description provided for @expandSidebar.
  ///
  /// In zh, this message translates to:
  /// **'展开侧边栏'**
  String get expandSidebar;

  /// No description provided for @serverConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{detail}'**
  String serverConnectionFailed(String detail);

  /// No description provided for @serverNetworkError.
  ///
  /// In zh, this message translates to:
  /// **'服务器 {url} 没有响应。请检查地址和端口，并确认服务端或反向代理正在运行。'**
  String serverNetworkError(String url);

  /// No description provided for @serverNetworkTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接 {url} 超时。请检查网络、防火墙和服务端状态。'**
  String serverNetworkTimeout(String url);

  /// No description provided for @serverInvalidResponse.
  ///
  /// In zh, this message translates to:
  /// **'已连接 {url}，但它没有返回兼容的 OpenLogTool Server 响应。'**
  String serverInvalidResponse(String url);

  /// No description provided for @serverAddressRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先填写服务器地址。'**
  String get serverAddressRequired;

  /// No description provided for @serverAddressInvalid.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址必须是完整的 http(s) URL。'**
  String get serverAddressInvalid;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'US':
            return AppLocalizationsEnUs();
        }
        break;
      }
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
