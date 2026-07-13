// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navWorkbench => 'Net Desk';

  @override
  String get navSessions => 'Sessions';

  @override
  String get navData => 'Data';

  @override
  String get navSettings => 'Settings';

  @override
  String get workbenchNoSession => 'No net in progress';

  @override
  String get workbenchLocalRecording => 'Local recording';

  @override
  String get collaborationLocalOnly => 'Local only';

  @override
  String get collaborationPublishing => 'Publishing';

  @override
  String get collaborationJoining => 'Joining';

  @override
  String get collaborationSnapshotting => 'Loading snapshot';

  @override
  String get collaborationCatchingUp => 'Catching up';

  @override
  String get collaborationReady => 'Connected';

  @override
  String get collaborationResyncing => 'Resyncing';

  @override
  String get collaborationRevoked => 'Access revoked';

  @override
  String get collaborationFailed => 'Sync failed';

  @override
  String collaborationState(String state) {
    return 'Collaboration: $state';
  }

  @override
  String pendingSyncCount(int count) {
    return 'Pending $count';
  }

  @override
  String conflictCount(int count) {
    return 'Conflicts $count';
  }

  @override
  String get localSessionTooltip => 'This is a local session';

  @override
  String collaborationStatusTooltip(String state, int count) {
    return 'Collaboration $state, $count pending';
  }

  @override
  String get currentRecord => 'Current record';

  @override
  String currentOrdinal(int ordinal) {
    return 'Current #$ordinal';
  }

  @override
  String get sessionsTitle => 'Sessions';

  @override
  String get sessionsSubtitle =>
      'Manage this net, collaborating scribes, and controller displays.';

  @override
  String get noCurrentSession => 'No current net session';

  @override
  String get noCurrentSessionHint =>
      'Create a session from the Net Desk to start logging.';

  @override
  String get sessionActive => 'Active';

  @override
  String get sessionClosed => 'Closed';

  @override
  String savedPositions(int count) {
    return '$count saved';
  }

  @override
  String get localSession => 'Local session';

  @override
  String get manageCollaboration => 'Collaboration & members';

  @override
  String get enterControllerScreen => 'Enter controller display';

  @override
  String get localControllerDisplay => 'Local controller display';

  @override
  String get localControllerDisplayHint =>
      'Keep logging in the main window while a separate read-only window serves the controller.';

  @override
  String get openFloatingWindow => 'Open floating window';

  @override
  String get openSecondDisplayWindow => 'Open second-display window';

  @override
  String get historySessions => 'Session history';

  @override
  String get historySessionsHint =>
      'For now, switch, close, and view past sessions from History in the Net Desk record area.';

  @override
  String controllerWindowOpenFailed(String error) {
    return 'Could not open controller window: $error';
  }

  @override
  String get controllerDisplaySettingsTitle => 'Controller display';

  @override
  String get enableControllerDeviceEntry => 'Enable controller-device entry';

  @override
  String get enableControllerDeviceEntryHint =>
      'When enabled, Sessions can open a full-screen read-only display on an Android tablet, phone, or separate computer.';

  @override
  String get defaultInformationDetail => 'Default information detail';

  @override
  String get desktopControllerDisplayHint =>
      'This desktop can also open an always-on-top window or a second-display window from Sessions.';

  @override
  String get inAppControllerDisplayHint =>
      'This device uses the in-app full-screen controller display.';

  @override
  String get controllerScreenTitle => 'OpenLogTool Controller Display';

  @override
  String get controllerFloatingWindowTitle =>
      'OpenLogTool Controller Floating Window';

  @override
  String get controllerScreenFallbackTitle => 'Net Controller Display';

  @override
  String savedPositionCount(int count) {
    return '$count saved';
  }

  @override
  String get notReceivedDraftUpdate => 'No draft update received';

  @override
  String updatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String editorEditing(String name) {
    return 'Editing by $name';
  }

  @override
  String get connectionConnected => 'Live';

  @override
  String get connectionReconnecting => 'Reconnecting';

  @override
  String get connectionOffline => 'Offline';

  @override
  String get staleControllerDataWarning =>
      'Connection lost. The last received content is shown and may be out of date.';

  @override
  String get previousSavedRecord => 'Previous saved record';

  @override
  String get noPreviousRecord => 'No previous record';

  @override
  String get waitingForCallsign => 'Waiting for a callsign…';

  @override
  String get beingEdited => 'Editing';

  @override
  String configureControllerDisplay(String detail) {
    return 'Display content ($detail)';
  }

  @override
  String get exitControllerScreen => 'Exit controller display';

  @override
  String get controllerDisplayConfiguration => 'Controller display content';

  @override
  String get informationDetail => 'Information detail';

  @override
  String get currentFields => 'Current fields';

  @override
  String get previousFields => 'Previous fields';

  @override
  String get cancel => 'Cancel';

  @override
  String get apply => 'Apply';

  @override
  String get detailMinimal => 'Minimal';

  @override
  String get detailStandard => 'Standard';

  @override
  String get detailFull => 'Full';

  @override
  String get detailCustom => 'Custom';

  @override
  String get fieldController => 'Controller';

  @override
  String get fieldCallsign => 'Callsign';

  @override
  String get fieldTime => 'Time';

  @override
  String get fieldRstSent => 'RST sent';

  @override
  String get fieldRstRcvd => 'RST received';

  @override
  String get fieldQth => 'QTH';

  @override
  String get fieldDevice => 'Radio';

  @override
  String get fieldPower => 'Power';

  @override
  String get fieldAntenna => 'Antenna';

  @override
  String get fieldHeight => 'Height';

  @override
  String get fieldRemarks => 'Remarks';

  @override
  String get saveRecord => 'Save record';

  @override
  String get recordAdded => 'Record saved';

  @override
  String get recordQueuedOffline => 'Saved offline; review after reconnecting';

  @override
  String get sharedDraftReadOnly => 'This shared draft is read-only';

  @override
  String fieldLockedBy(String name) {
    return 'Editing by $name';
  }

  @override
  String get offlineReviewTitle => 'Offline records need review';

  @override
  String get resolutionDiscard => 'Discard';

  @override
  String get resolutionSubmitDuplicate => 'Submit as duplicate';

  @override
  String get resolutionCopyCurrent => 'Copy to current draft';

  @override
  String get callsignRequired => 'Enter a callsign';

  @override
  String get leaveSession => 'Leave collaboration session';

  @override
  String get leaveSessionConfirmation =>
      'After leaving, the local replica remains read-only. A new invitation is required to participate again.';

  @override
  String get confirm => 'Confirm';

  @override
  String get duplicateCallsignWarningSetting => 'Duplicate callsign warning';

  @override
  String get duplicateCallsignWarningHint =>
      'Warn before saving the same callsign again in this net, while still allowing it.';

  @override
  String get duplicateCallsignTitle => 'Callsign already recorded';

  @override
  String duplicateCallsignMessage(String callsign) {
    return '$callsign is already recorded in this net. Save it again?';
  }

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String get callsignHistoryFillSetting => 'Reuse callsign history';

  @override
  String get callsignHistoryFillHint =>
      'Match existing callsign records and fill the radio, antenna, QTH, and related fields in one tap.';

  @override
  String get publicShareManagement => 'Public controller page';

  @override
  String get publicShareManagementHint =>
      'Available only when the server also provides the safe public page. The link secret is shown only when created.';

  @override
  String get createPublicShare => 'Create public link';

  @override
  String get copyPublicShareLink => 'Copy link';

  @override
  String get revokePublicShare => 'Revoke';

  @override
  String get publicShareLinkCopied => 'Public link copied';

  @override
  String publicShareExpiresAt(String time) {
    return 'Expires $time';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get reuseDatabaseInformation => 'Reuse database information';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get expandSidebar => 'Expand sidebar';

  @override
  String serverConnectionFailed(String detail) {
    return 'Connection failed: $detail';
  }

  @override
  String serverNetworkError(String url) {
    return 'The server at $url did not respond. Check the address and port, and make sure the server or reverse proxy is running.';
  }

  @override
  String serverNetworkTimeout(String url) {
    return 'The connection to $url timed out. Check the network, firewall, and server status.';
  }

  @override
  String serverInvalidResponse(String url) {
    return 'Connected to $url, but it did not return a compatible OpenLogTool Server response.';
  }

  @override
  String get serverAddressRequired => 'Enter a server address first.';

  @override
  String get serverAddressInvalid =>
      'The server address must be a complete http(s) URL.';

  @override
  String get excelUseSessionTitleAsHeader =>
      'Use current session name as header';

  @override
  String get excelUseSessionTitleAsHeaderHint =>
      'Use the current session name directly as the Excel header. If it is blank, the header template is used instead.';

  @override
  String get themeColorPickerTitle => 'Choose theme color';

  @override
  String get themeColorPresets => 'Preset colors';

  @override
  String get themeColorCustom => 'Custom color';

  @override
  String get themeColorHex => 'HEX color';

  @override
  String get themeColorHue => 'Hue';

  @override
  String get themeColorBlue => 'Blue';

  @override
  String get themeColorGreen => 'Green';

  @override
  String get themeColorRed => 'Red';

  @override
  String get themeColorOrange => 'Orange';

  @override
  String get themeColorPurple => 'Purple';

  @override
  String get themeColorPink => 'Pink';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get renameSession => 'Rename session';

  @override
  String get renameSessionTitle => 'Rename session';

  @override
  String get sessionTitleLabel => 'Session name';

  @override
  String get renameCollaborationSessionHint =>
      'Only the session owner can rename it. The new name will sync to other scribes and controller displays.';

  @override
  String get renameSessionSaved => 'Session name updated';

  @override
  String get renameCollaborationSessionSaved =>
      'Session name saved and syncing to other members';

  @override
  String renameSessionFailed(String error) {
    return 'Could not rename session: $error';
  }

  @override
  String get renameSessionBlockedClosed => 'A closed session cannot be renamed';

  @override
  String get renameSessionBlockedBusy =>
      'Wait for the current collaboration operation to finish';

  @override
  String get renameSessionBlockedConflict =>
      'Resolve the session conflict before renaming';

  @override
  String get renameSessionBlockedNotReady =>
      'The collaboration session is not ready to be renamed';

  @override
  String get renameSessionBlockedOwner =>
      'Only the session owner can rename it';

  @override
  String get dictionaryManagementTitle => 'Lookup libraries';

  @override
  String get dictionaryManagementHint =>
      'Manage radios, antennas, callsigns, and QTH values that can be searched and reused while logging.';

  @override
  String get deviceLibrary => 'Radio library';

  @override
  String get antennaLibrary => 'Antenna library';

  @override
  String get callsignLibrary => 'Callsign library';

  @override
  String get qthLibrary => 'QTH library';

  @override
  String libraryItemCount(int count) {
    return '$count entries';
  }

  @override
  String get importLibraryJson => 'Import JSON';

  @override
  String get expandAll => 'Expand all';

  @override
  String get collapseAll => 'Collapse all';

  @override
  String addLibraryItem(String name) {
    return 'Add to $name';
  }

  @override
  String searchLibrary(String name) {
    return 'Search $name';
  }

  @override
  String get libraryEmpty => 'This library is empty';

  @override
  String get noLibrarySearchResults => 'No matching library entries';

  @override
  String libraryItemAdded(String value) {
    return 'Added: $value';
  }

  @override
  String libraryItemAlreadyExists(String value) {
    return '“$value” is already in the library';
  }

  @override
  String libraryItemAddFailed(String error) {
    return 'Could not add entry: $error';
  }

  @override
  String get libraryImportEmpty => 'The file has no library entries to import';

  @override
  String libraryImportCount(String name, int count) {
    return '$name: $count';
  }

  @override
  String libraryImportSucceeded(String summary) {
    return 'Imported: $summary';
  }

  @override
  String libraryImportFailed(String error) {
    return 'Could not import libraries: $error';
  }

  @override
  String get listSeparator => ', ';

  @override
  String get fontPickerTitle => 'Choose font';

  @override
  String get fontSearchHint => 'Search fonts';

  @override
  String fontResultCount(int count) {
    return '$count fonts';
  }

  @override
  String get fontSystemDefault => 'System default';

  @override
  String get fontBuiltIn => 'Built in';

  @override
  String get fontPreview => 'Preview';

  @override
  String get fontPreviewSample => 'OpenLogTool · CQ CQ · Net log 123';
}

/// The translations for English, as used in the United States (`en_US`).
class AppLocalizationsEnUs extends AppLocalizationsEn {
  AppLocalizationsEnUs() : super('en_US');

  @override
  String get navWorkbench => 'Net Desk';

  @override
  String get navSessions => 'Sessions';

  @override
  String get navData => 'Data';

  @override
  String get navSettings => 'Settings';

  @override
  String get workbenchNoSession => 'No net in progress';

  @override
  String get workbenchLocalRecording => 'Local recording';

  @override
  String get collaborationLocalOnly => 'Local only';

  @override
  String get collaborationPublishing => 'Publishing';

  @override
  String get collaborationJoining => 'Joining';

  @override
  String get collaborationSnapshotting => 'Loading snapshot';

  @override
  String get collaborationCatchingUp => 'Catching up';

  @override
  String get collaborationReady => 'Connected';

  @override
  String get collaborationResyncing => 'Resyncing';

  @override
  String get collaborationRevoked => 'Access revoked';

  @override
  String get collaborationFailed => 'Sync failed';

  @override
  String collaborationState(String state) {
    return 'Collaboration: $state';
  }

  @override
  String pendingSyncCount(int count) {
    return 'Pending $count';
  }

  @override
  String conflictCount(int count) {
    return 'Conflicts $count';
  }

  @override
  String get localSessionTooltip => 'This is a local session';

  @override
  String collaborationStatusTooltip(String state, int count) {
    return 'Collaboration $state, $count pending';
  }

  @override
  String get currentRecord => 'Current record';

  @override
  String currentOrdinal(int ordinal) {
    return 'Current #$ordinal';
  }

  @override
  String get sessionsTitle => 'Sessions';

  @override
  String get sessionsSubtitle =>
      'Manage this net, collaborating scribes, and controller displays.';

  @override
  String get noCurrentSession => 'No current net session';

  @override
  String get noCurrentSessionHint =>
      'Create a session from the Net Desk to start logging.';

  @override
  String get sessionActive => 'Active';

  @override
  String get sessionClosed => 'Closed';

  @override
  String savedPositions(int count) {
    return '$count saved';
  }

  @override
  String get localSession => 'Local session';

  @override
  String get manageCollaboration => 'Collaboration & members';

  @override
  String get enterControllerScreen => 'Enter controller display';

  @override
  String get localControllerDisplay => 'Local controller display';

  @override
  String get localControllerDisplayHint =>
      'Keep logging in the main window while a separate read-only window serves the controller.';

  @override
  String get openFloatingWindow => 'Open floating window';

  @override
  String get openSecondDisplayWindow => 'Open second-display window';

  @override
  String get historySessions => 'Session history';

  @override
  String get historySessionsHint =>
      'For now, switch, close, and view past sessions from History in the Net Desk record area.';

  @override
  String controllerWindowOpenFailed(String error) {
    return 'Could not open controller window: $error';
  }

  @override
  String get controllerDisplaySettingsTitle => 'Controller display';

  @override
  String get enableControllerDeviceEntry => 'Enable controller-device entry';

  @override
  String get enableControllerDeviceEntryHint =>
      'When enabled, Sessions can open a full-screen read-only display on an Android tablet, phone, or separate computer.';

  @override
  String get defaultInformationDetail => 'Default information detail';

  @override
  String get desktopControllerDisplayHint =>
      'This desktop can also open an always-on-top window or a second-display window from Sessions.';

  @override
  String get inAppControllerDisplayHint =>
      'This device uses the in-app full-screen controller display.';

  @override
  String get controllerScreenTitle => 'OpenLogTool Controller Display';

  @override
  String get controllerFloatingWindowTitle =>
      'OpenLogTool Controller Floating Window';

  @override
  String get controllerScreenFallbackTitle => 'Net Controller Display';

  @override
  String savedPositionCount(int count) {
    return '$count saved';
  }

  @override
  String get notReceivedDraftUpdate => 'No draft update received';

  @override
  String updatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String editorEditing(String name) {
    return 'Editing by $name';
  }

  @override
  String get connectionConnected => 'Live';

  @override
  String get connectionReconnecting => 'Reconnecting';

  @override
  String get connectionOffline => 'Offline';

  @override
  String get staleControllerDataWarning =>
      'Connection lost. The last received content is shown and may be out of date.';

  @override
  String get previousSavedRecord => 'Previous saved record';

  @override
  String get noPreviousRecord => 'No previous record';

  @override
  String get waitingForCallsign => 'Waiting for a callsign…';

  @override
  String get beingEdited => 'Editing';

  @override
  String configureControllerDisplay(String detail) {
    return 'Display content ($detail)';
  }

  @override
  String get exitControllerScreen => 'Exit controller display';

  @override
  String get controllerDisplayConfiguration => 'Controller display content';

  @override
  String get informationDetail => 'Information detail';

  @override
  String get currentFields => 'Current fields';

  @override
  String get previousFields => 'Previous fields';

  @override
  String get cancel => 'Cancel';

  @override
  String get apply => 'Apply';

  @override
  String get detailMinimal => 'Minimal';

  @override
  String get detailStandard => 'Standard';

  @override
  String get detailFull => 'Full';

  @override
  String get detailCustom => 'Custom';

  @override
  String get fieldController => 'Controller';

  @override
  String get fieldCallsign => 'Callsign';

  @override
  String get fieldTime => 'Time';

  @override
  String get fieldRstSent => 'RST sent';

  @override
  String get fieldRstRcvd => 'RST received';

  @override
  String get fieldQth => 'QTH';

  @override
  String get fieldDevice => 'Radio';

  @override
  String get fieldPower => 'Power';

  @override
  String get fieldAntenna => 'Antenna';

  @override
  String get fieldHeight => 'Height';

  @override
  String get fieldRemarks => 'Remarks';

  @override
  String get saveRecord => 'Save record';

  @override
  String get recordAdded => 'Record saved';

  @override
  String get recordQueuedOffline => 'Saved offline; review after reconnecting';

  @override
  String get sharedDraftReadOnly => 'This shared draft is read-only';

  @override
  String fieldLockedBy(String name) {
    return 'Editing by $name';
  }

  @override
  String get offlineReviewTitle => 'Offline records need review';

  @override
  String get resolutionDiscard => 'Discard';

  @override
  String get resolutionSubmitDuplicate => 'Submit as duplicate';

  @override
  String get resolutionCopyCurrent => 'Copy to current draft';

  @override
  String get callsignRequired => 'Enter a callsign';

  @override
  String get leaveSession => 'Leave collaboration session';

  @override
  String get leaveSessionConfirmation =>
      'After leaving, the local replica remains read-only. A new invitation is required to participate again.';

  @override
  String get confirm => 'Confirm';

  @override
  String get duplicateCallsignWarningSetting => 'Duplicate callsign warning';

  @override
  String get duplicateCallsignWarningHint =>
      'Warn before saving the same callsign again in this net, while still allowing it.';

  @override
  String get duplicateCallsignTitle => 'Callsign already recorded';

  @override
  String duplicateCallsignMessage(String callsign) {
    return '$callsign is already recorded in this net. Save it again?';
  }

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String get callsignHistoryFillSetting => 'Reuse callsign history';

  @override
  String get callsignHistoryFillHint =>
      'Match existing callsign records and fill the radio, antenna, QTH, and related fields in one tap.';

  @override
  String get publicShareManagement => 'Public controller page';

  @override
  String get publicShareManagementHint =>
      'Available only when the server also provides the safe public page. The link secret is shown only when created.';

  @override
  String get createPublicShare => 'Create public link';

  @override
  String get copyPublicShareLink => 'Copy link';

  @override
  String get revokePublicShare => 'Revoke';

  @override
  String get publicShareLinkCopied => 'Public link copied';

  @override
  String publicShareExpiresAt(String time) {
    return 'Expires $time';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get reuseDatabaseInformation => 'Reuse database information';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get expandSidebar => 'Expand sidebar';

  @override
  String serverConnectionFailed(String detail) {
    return 'Connection failed: $detail';
  }

  @override
  String serverNetworkError(String url) {
    return 'The server at $url did not respond. Check the address and port, and make sure the server or reverse proxy is running.';
  }

  @override
  String serverNetworkTimeout(String url) {
    return 'The connection to $url timed out. Check the network, firewall, and server status.';
  }

  @override
  String serverInvalidResponse(String url) {
    return 'Connected to $url, but it did not return a compatible OpenLogTool Server response.';
  }

  @override
  String get serverAddressRequired => 'Enter a server address first.';

  @override
  String get serverAddressInvalid =>
      'The server address must be a complete http(s) URL.';

  @override
  String get excelUseSessionTitleAsHeader =>
      'Use current session name as header';

  @override
  String get excelUseSessionTitleAsHeaderHint =>
      'Use the current session name directly as the Excel header. If it is blank, the header template is used instead.';

  @override
  String get themeColorPickerTitle => 'Choose theme color';

  @override
  String get themeColorPresets => 'Preset colors';

  @override
  String get themeColorCustom => 'Custom color';

  @override
  String get themeColorHex => 'HEX color';

  @override
  String get themeColorHue => 'Hue';

  @override
  String get themeColorBlue => 'Blue';

  @override
  String get themeColorGreen => 'Green';

  @override
  String get themeColorRed => 'Red';

  @override
  String get themeColorOrange => 'Orange';

  @override
  String get themeColorPurple => 'Purple';

  @override
  String get themeColorPink => 'Pink';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get renameSession => 'Rename session';

  @override
  String get renameSessionTitle => 'Rename session';

  @override
  String get sessionTitleLabel => 'Session name';

  @override
  String get renameCollaborationSessionHint =>
      'Only the session owner can rename it. The new name will sync to other scribes and controller displays.';

  @override
  String get renameSessionSaved => 'Session name updated';

  @override
  String get renameCollaborationSessionSaved =>
      'Session name saved and syncing to other members';

  @override
  String renameSessionFailed(String error) {
    return 'Could not rename session: $error';
  }

  @override
  String get renameSessionBlockedClosed => 'A closed session cannot be renamed';

  @override
  String get renameSessionBlockedBusy =>
      'Wait for the current collaboration operation to finish';

  @override
  String get renameSessionBlockedConflict =>
      'Resolve the session conflict before renaming';

  @override
  String get renameSessionBlockedNotReady =>
      'The collaboration session is not ready to be renamed';

  @override
  String get renameSessionBlockedOwner =>
      'Only the session owner can rename it';

  @override
  String get dictionaryManagementTitle => 'Lookup libraries';

  @override
  String get dictionaryManagementHint =>
      'Manage radios, antennas, callsigns, and QTH values that can be searched and reused while logging.';

  @override
  String get deviceLibrary => 'Radio library';

  @override
  String get antennaLibrary => 'Antenna library';

  @override
  String get callsignLibrary => 'Callsign library';

  @override
  String get qthLibrary => 'QTH library';

  @override
  String libraryItemCount(int count) {
    return '$count entries';
  }

  @override
  String get importLibraryJson => 'Import JSON';

  @override
  String get expandAll => 'Expand all';

  @override
  String get collapseAll => 'Collapse all';

  @override
  String addLibraryItem(String name) {
    return 'Add to $name';
  }

  @override
  String searchLibrary(String name) {
    return 'Search $name';
  }

  @override
  String get libraryEmpty => 'This library is empty';

  @override
  String get noLibrarySearchResults => 'No matching library entries';

  @override
  String libraryItemAdded(String value) {
    return 'Added: $value';
  }

  @override
  String libraryItemAlreadyExists(String value) {
    return '“$value” is already in the library';
  }

  @override
  String libraryItemAddFailed(String error) {
    return 'Could not add entry: $error';
  }

  @override
  String get libraryImportEmpty => 'The file has no library entries to import';

  @override
  String libraryImportCount(String name, int count) {
    return '$name: $count';
  }

  @override
  String libraryImportSucceeded(String summary) {
    return 'Imported: $summary';
  }

  @override
  String libraryImportFailed(String error) {
    return 'Could not import libraries: $error';
  }

  @override
  String get listSeparator => ', ';

  @override
  String get fontPickerTitle => 'Choose font';

  @override
  String get fontSearchHint => 'Search fonts';

  @override
  String fontResultCount(int count) {
    return '$count fonts';
  }

  @override
  String get fontSystemDefault => 'System default';

  @override
  String get fontBuiltIn => 'Built in';

  @override
  String get fontPreview => 'Preview';

  @override
  String get fontPreviewSample => 'OpenLogTool · CQ CQ · Net log 123';
}
