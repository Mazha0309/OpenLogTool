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
  String get startNewRecord => 'Start new record';

  @override
  String get newRecordName => 'New record name';

  @override
  String get newRecordNameHint => 'Enter a name for this record (optional)';

  @override
  String get automaticName => 'automatic name';

  @override
  String newRecordStarted(String name) {
    return 'Started new record: $name';
  }

  @override
  String createNewRecordFailed(String error) {
    return 'Could not create a new record: $error';
  }

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
  String get openLiveShare => 'Live Share';

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
      'View and switch to past net sessions. Closed sessions open read-only.';

  @override
  String get historySessionsEmpty => 'There are no past sessions';

  @override
  String historySessionsLoadFailed(String error) {
    return 'Could not load session history: $error';
  }

  @override
  String get historySessionOpen => 'Open session';

  @override
  String get historySessionCurrent => 'Current session';

  @override
  String historySessionSwitched(String title) {
    return 'Opened session: $title';
  }

  @override
  String historySessionOpenFailed(String error) {
    return 'Could not open session: $error';
  }

  @override
  String get historySessionCloseTitle => 'Close session';

  @override
  String historySessionCloseConfirmation(String title) {
    return 'Close “$title”? It will remain available read-only in Session history.';
  }

  @override
  String get historySessionClosed => 'Session closed';

  @override
  String historySessionCloseFailed(String error) {
    return 'Could not close session: $error';
  }

  @override
  String get historySessionCollaborationCloseRequiresOpen =>
      'This is a collaboration session. Open it first, then close it from Collaboration & members.';

  @override
  String get historySessionCollaborationCloseOwnerRequired =>
      'Only a fully synchronized session owner can close a collaboration session. Refresh access in Collaboration & members and try again.';

  @override
  String get historySessionReopenAction => 'Reactivate';

  @override
  String get historySessionReopenTitle => 'Reactivate local session';

  @override
  String historySessionReopenConfirmation(String title) {
    return 'Reactivate “$title” and switch to it? Any other active local session will be closed automatically; collaboration sessions are not affected. Reopen a collaboration target from Collaboration & members.';
  }

  @override
  String historySessionReopened(String title) {
    return 'Reactivated and switched to session: $title';
  }

  @override
  String historySessionReopenFailed(String error) {
    return 'Could not reactivate local session: $error';
  }

  @override
  String historySessionReopenedLogsUnavailable(String title) {
    return 'Session “$title” was reactivated, but its logs could not be loaded. It is temporarily read-only; retry loading.';
  }

  @override
  String get historySessionCollaborationReopenRequired =>
      'This is a collaboration session. Open it first, then reopen it from Collaboration & members.';

  @override
  String get historySessionDeleteTitle => 'Permanently delete local session';

  @override
  String historySessionDeleteWarning(String title) {
    return 'This permanently deletes all local logs and the local collaboration replica for “$title”. This cannot be undone, but it will not delete or close the shared session on the server. Enter the full session name to confirm:';
  }

  @override
  String get historySessionDeleteNameLabel => 'Full session name';

  @override
  String historySessionDeleteExpectedName(String title) {
    return 'Expected: $title';
  }

  @override
  String get historySessionDeleteNameMismatch =>
      'The session name does not match. Check every character.';

  @override
  String get historySessionDeleteAction => 'Delete local data permanently';

  @override
  String get historySessionDeleted => 'Local session permanently deleted';

  @override
  String historySessionDeleteFailed(String error) {
    return 'Could not permanently delete local session: $error';
  }

  @override
  String get historySessionReadOnly =>
      'This is a closed historical session. Existing records are read-only.';

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
  String get logTimeInvalid => 'Enter a valid time (HH:mm)';

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
  String get finishEditing => 'Finish editing';

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
  String get convertCollaborationToLocal =>
      'Stop collaboration on this device and convert to a local session';

  @override
  String get convertCollaborationToLocalTitle =>
      'Stop collaboration on this device?';

  @override
  String convertCollaborationToLocalConfirmation(String title) {
    return 'This stops collaboration synchronization for “$title” on this device and internally replaces the current session with an editable local copy. The shared server session, its members, and other devices are not affected. This cannot be undone.';
  }

  @override
  String get convertCollaborationToLocalSucceeded =>
      'Stopped collaboration on this device and converted to a local session';

  @override
  String get createEditableLocalCopy => 'Stop syncing and create local copy';

  @override
  String get createEditableLocalCopyTitle => 'Stop syncing on this device?';

  @override
  String createEditableLocalCopyConfirmation(String title) {
    return 'This creates an independent copy of “$title” on this device, copies every saved record currently shown in the table, and switches to it immediately. The new copy can be edited offline and will no longer synchronize. The shared server session and its original local replica will not be closed or deleted. Collaboration queues, conflicts, and an unsubmitted live draft stay with the original replica and are not copied.';
  }

  @override
  String editableLocalCopySessionTitle(String title) {
    return '$title (local copy)';
  }

  @override
  String get editableLocalCopySucceeded =>
      'Switched to the editable local copy';

  @override
  String get collaborationScreenTitle => 'Collaboration and members';

  @override
  String get collaborationConnectionSection => 'Connection and session';

  @override
  String get collaborationConnectionSectionHint =>
      'Review the server account, current session, and synchronization entry points.';

  @override
  String get collaborationSyncSection => 'Synchronization review';

  @override
  String get collaborationSyncSectionHint =>
      'Review offline records and resolve conflicts that require a decision.';

  @override
  String get collaborationAccessSection => 'Members and sharing';

  @override
  String get collaborationAccessSectionHint =>
      'Manage scribe access, invitation codes, and read-only public pages.';

  @override
  String get serverLoggedIn => 'Signed in';

  @override
  String get serverNotLoggedIn => 'Not signed in to a server';

  @override
  String collaborationServerAccount(String url, String id) {
    return '$url\nAccount $id';
  }

  @override
  String get collaborationServerLoginHint =>
      'Check the server and sign in from Settings → Server and account.';

  @override
  String get remoteCommitPendingLocalApplyHint =>
      'The remote commit succeeded. The client will restore only the local acknowledgement and will not create another mutation.';

  @override
  String get joinCollaborationTitle => 'Join collaboration';

  @override
  String get joinCollaborationHint =>
      'Enter a member invitation code. A complete local replica is installed with the same remote Session ID.';

  @override
  String get inviteCodeLabel => 'Invitation code';

  @override
  String get join => 'Join';

  @override
  String get joinCollaborationSucceeded => 'Joined the collaboration session';

  @override
  String get localCollaborationSessionHint =>
      'This local session is not published. Publishing locks a consistent snapshot and uploads all records in batches.';

  @override
  String collaborationSessionSummary(String state, String role) {
    return 'Status $state · Role $role';
  }

  @override
  String collaborationSyncSummary(String transport, int applied, int head) {
    return 'Sync $transport · Cursor $applied/$head';
  }

  @override
  String collaborationQueueSummary(int pending, int conflicts, int rejected) {
    return 'Pending $pending · Conflicts $conflicts · Rejected $rejected';
  }

  @override
  String get collaborationReliableQueueHint =>
      'Local saves enter the reliable queue and are confirmed by canonical events.';

  @override
  String collaborationLastSync(String time) {
    return 'Last synchronized $time';
  }

  @override
  String get collaborationSessionConflictHint =>
      'The session has an unresolved conflict. Resolve it first; rename, close, and reopen actions are temporarily unavailable.';

  @override
  String get publishSessionSucceeded => 'Collaboration session published';

  @override
  String get publishCollaborationSession => 'Publish for collaboration';

  @override
  String get retryPublishSession => 'Retry publishing';

  @override
  String get syncNowAndRefreshAccess => 'Sync now and refresh access';

  @override
  String get closeSession => 'Close session';

  @override
  String get reopenSession => 'Reopen';

  @override
  String get transportStopped => 'Stopped';

  @override
  String get transportConnecting => 'Connecting';

  @override
  String get transportOnline => 'Online';

  @override
  String get transportBackingOff => 'Waiting to reconnect';

  @override
  String get transportAuthRequired => 'Sign-in required';

  @override
  String get transportIncompatible => 'Protocol error';

  @override
  String get readOnlyRevoked =>
      'Membership has been revoked. The local cache is read-only.';

  @override
  String get readOnlyClosePending =>
      'The close request is saved locally and awaits confirmation; the session remains locked if it conflicts.';

  @override
  String get readOnlyReopenPending =>
      'The reopen request is saved locally. The session remains read-only until the server confirms it.';

  @override
  String get readOnlySessionClosed =>
      'The collaboration session is closed. The local cache is read-only.';

  @override
  String get readOnlyViewer => 'This account is a read-only member.';

  @override
  String get readOnlyResyncing =>
      'The event cursor requires a canonical snapshot reinstall; pending changes are preserved.';

  @override
  String get readOnlyCheckingAccess =>
      'Access and the event cursor are being checked. The session is temporarily read-only.';

  @override
  String get logNotOwnedReadOnlyHint =>
      'You can change or delete only records that you created.';

  @override
  String get logAuthorUnknownReadOnlyHint =>
      'This historical record has no author information and is read-only for members.';

  @override
  String get logSessionReadOnlyHint =>
      'The current member role, session state, or synchronization state does not allow record changes.';

  @override
  String get logConflictReadOnlyHint =>
      'Resolve this record in the conflict center first.';

  @override
  String get renameCollaborationSession => 'Rename collaboration session';

  @override
  String get saveLocally => 'Save locally';

  @override
  String get sessionTitleQueued =>
      'Title saved locally and awaiting synchronization';

  @override
  String get closeCollaborationSessionTitle => 'Close collaboration session';

  @override
  String get closeCollaborationSessionMessage =>
      'After closing, no member can add or change records. The owner can reopen the session later.';

  @override
  String get closeCollaborationDraftNotEmpty =>
      'The current live draft still contains data. Submit the complete record, or explicitly discard the draft before closing.';

  @override
  String get closeCollaborationDraftIncomplete =>
      'The draft is missing its time, controller callsign, or logged callsign, so it cannot be submitted. You can still discard it and close.';

  @override
  String closeCollaborationDraftLocked(int count) {
    return 'Another member or device is editing $count draft fields. Wait for those edits to finish, then refresh before closing.';
  }

  @override
  String get closeCollaborationDiscardAndClose => 'Discard draft and close';

  @override
  String get closeCollaborationSubmitAndClose => 'Submit and close';

  @override
  String get closeCollaborationQueuedOffline =>
      'The record was saved only to the offline queue and has not reached the server. The session was not closed. Reconnect and resolve the record before retrying.';

  @override
  String get closeSessionQueued =>
      'Session closed locally and awaiting synchronization';

  @override
  String get reopenCollaborationSessionTitle => 'Reopen collaboration session';

  @override
  String get reopenCollaborationSessionMessage =>
      'Reopening is submitted as a synchronized change. The session remains read-only until confirmed.';

  @override
  String get reopenSessionQueued =>
      'Reopen request saved locally and awaiting synchronization';

  @override
  String get conflictUseRemoteTitle => 'Use remote version';

  @override
  String get conflictKeepLocalTitle => 'Keep local version';

  @override
  String get conflictCopyLocalTitle => 'Copy as a new log';

  @override
  String get conflictUseRemoteMessage =>
      'Unsynchronized local changes are replaced by the canonical remote version. No new mutation is submitted.';

  @override
  String get conflictKeepLocalMessage =>
      'A new mutation is based on the latest remote version. Another remote change can still produce a new conflict.';

  @override
  String get conflictCopyLocalMessage =>
      'The remote log is preserved, while the local content is copied under a new log ID and synchronized again.';

  @override
  String get conflictUseRemoteSucceeded => 'Remote version applied';

  @override
  String get conflictKeepLocalSucceeded =>
      'Local version kept and queued for retry';

  @override
  String get conflictCopyLocalSucceeded =>
      'Copied as a new log and queued for synchronization';

  @override
  String get conflictCenterTitle => 'Conflict center';

  @override
  String get refreshConflicts => 'Refresh conflicts';

  @override
  String get conflictCenterHint =>
      'Available actions reflect the latest access and entity state in the local replica. Keeping or copying creates a new synchronized mutation.';

  @override
  String get noConflicts => 'No conflicts need attention.';

  @override
  String get conflictSession => 'Session';

  @override
  String get conflictLog => 'Log';

  @override
  String get conflictNoOverlappingFields =>
      'No overlapping fields (the version changed)';

  @override
  String conflictVersionSummary(String fields, int base, int remote) {
    return 'Fields $fields · Base v$base → remote v$remote';
  }

  @override
  String get conflictBase => 'Base';

  @override
  String get conflictLocal => 'Local';

  @override
  String get conflictRemote => 'Remote';

  @override
  String get conflictUseRemoteAction => 'Use remote';

  @override
  String get conflictKeepLocalAction => 'Keep local and retry';

  @override
  String get conflictCopyLocalAction => 'Copy as a new log';

  @override
  String get memberInvitesTitle => 'Member invitations';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleEditor => 'Editor';

  @override
  String get roleViewer => 'Read-only member';

  @override
  String get inviteCreated => 'Invitation code created';

  @override
  String get generate => 'Generate';

  @override
  String get inviteCodeOneTimeHint =>
      'The invitation code is shown only in this creation response:';

  @override
  String get noInvites => 'No invitations';

  @override
  String inviteSummary(int used, int max, String status) {
    return '$used/$max uses · $status';
  }

  @override
  String inviteExpiresAt(String time) {
    return 'Expires $time';
  }

  @override
  String get inviteRevoked => 'Revoked';

  @override
  String get membersTitle => 'Members';

  @override
  String get currentAccount => 'Current account';

  @override
  String get memberSetEditor => 'Member changed to editor';

  @override
  String get memberSetViewer => 'Member changed to read-only';

  @override
  String get setAsEditor => 'Make editor';

  @override
  String get setAsViewer => 'Make read-only';

  @override
  String get transferOwnership => 'Transfer ownership';

  @override
  String get removeMember => 'Remove member';

  @override
  String transferOwnershipConfirmation(String name) {
    return 'After transferring to $name, you become an editor.';
  }

  @override
  String get ownershipTransferred => 'Ownership transferred';

  @override
  String removeMemberConfirmation(String name) {
    return 'Remove $name? Their access is revoked immediately.';
  }

  @override
  String get memberRemoved => 'Member removed';

  @override
  String operationFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String get unknown => 'Unknown';

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
  String get publicShareManagement => 'Live Share · public read-only page';

  @override
  String get publicShareManagementHint =>
      'Create a read-only web page for controllers, remote scribes, or observers. It can be viewed without signing in; the link secret is shown only when created.';

  @override
  String get publicShareAccessRequired =>
      'Live Share is managed by the collaboration session owner. Sign in and publish this session first, or ask the owner to create the public link.';

  @override
  String get publicShareUnsupported =>
      'This server does not provide the secure Live Share page. Upgrade or enable public sharing on the server to create one.';

  @override
  String get publicShareCreatedTitle => 'Public read-only page created';

  @override
  String get publicShareCreatedHint =>
      'Save this link now. For security, its secret cannot be retrieved again after a refresh or sign-in.';

  @override
  String get createPublicShare => 'Create public link';

  @override
  String get copyPublicShareLink => 'Copy link';

  @override
  String get openPublicShare => 'Open in browser';

  @override
  String get revokePublicShare => 'Revoke';

  @override
  String get publicShareLinkCopied => 'Public link copied';

  @override
  String get publicShareNoActiveLinks =>
      'There are no active public links. Create one for a controller or remote observer.';

  @override
  String get publicShareSecretUnavailable =>
      'An active public link exists, but its secret was returned only when created. If it was not saved, revoke it and create a new link.';

  @override
  String get publicShareLinksTitle => 'Public link history';

  @override
  String get publicShareUnavailable => 'Revoked or expired';

  @override
  String get publicShareOpenFailed =>
      'Could not open the browser. You can still copy the link and open it manually.';

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
  String get limitWorkbenchWidthSetting => 'Limit Net Desk content width';

  @override
  String get limitWorkbenchWidthHint =>
      'Center Net Desk content and limit it to 1440 pixels on wide screens to keep fields from stretching too far.';

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
  String get serverSettingsTitle => 'Server and account';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get serverAddressHint => 'http://your-server:3000';

  @override
  String get serverSaveAndCheck => 'Save and check server';

  @override
  String serverCheckSucceeded(int min, int max) {
    return 'Connected · protocol v$min-$max';
  }

  @override
  String serverInstanceDetails(String instance, String features) {
    return 'Instance $instance\nCapabilities $features';
  }

  @override
  String get serverConnected => 'Connected';

  @override
  String get serverNotConnected => 'Not checked';

  @override
  String get serverSignedOutHint =>
      'Sign in to collaborate and manage only your own account and sign-in devices.';

  @override
  String get tokenStoragePrivateFileWarning =>
      'The system keyring is unavailable. Your sign-in is stored in a private file readable only by your Linux user and will move back to secure storage when a keyring becomes available.';

  @override
  String get tokenStorageMemoryOnlyWarning =>
      'Secure credential storage is unavailable. This sign-in lasts only while the app is running; you will need to sign in again after exiting.';

  @override
  String get serverLogin => 'Sign in';

  @override
  String get serverRegister => 'Register';

  @override
  String get serverLogout => 'Sign out';

  @override
  String serverAccountId(String id) {
    return 'Account ID: $id';
  }

  @override
  String get serverLoginSucceeded => 'Signed in to the server';

  @override
  String get serverRegistrationSucceeded => 'Registered and signed in';

  @override
  String serverLoginFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String serverRegistrationFailed(String error) {
    return 'Registration failed: $error';
  }

  @override
  String serverLogoutFailed(String error) {
    return 'Sign-out failed: $error';
  }

  @override
  String get accountChangeUsername => 'Change username';

  @override
  String get accountChangePassword => 'Change password';

  @override
  String get accountDeviceSessions => 'Sign-in devices';

  @override
  String get accountUsernameUpdated => 'Username updated';

  @override
  String accountPasswordUpdated(int count) {
    return 'Password updated. $count sign-in sessions were revoked; sign in again.';
  }

  @override
  String accountUpdateFailed(String error) {
    return 'Account action failed: $error';
  }

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameLengthHint => 'Username must be 3–64 characters';

  @override
  String get passwordLabel => 'Password';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get currentPasswordLabel => 'Current password';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get confirmNewPasswordLabel => 'Confirm new password';

  @override
  String get passwordLengthHint => 'Password must be at least 10 characters';

  @override
  String get passwordMismatch => 'The new passwords do not match';

  @override
  String get passwordChangeRequiredTitle =>
      'Temporary password must be changed';

  @override
  String passwordChangeRequiredHint(String username) {
    return 'Account $username signed in with a temporary password. Set a new password to continue.';
  }

  @override
  String passwordChangeCredentialExpires(int seconds) {
    return 'This password-change credential expires in $seconds seconds.';
  }

  @override
  String get completePasswordChange => 'Set password and sign in';

  @override
  String get cancelLogin => 'Cancel sign-in';

  @override
  String get passwordChangeCompleted =>
      'Password updated and sign-in completed';

  @override
  String get deviceSessionsTitle => 'Sign-in devices';

  @override
  String get deviceSessionsEmpty => 'There are no active sign-in devices';

  @override
  String get deviceUnknown => 'Unnamed device';

  @override
  String get deviceCurrent => 'Current device';

  @override
  String deviceIp(String ip) {
    return 'IP: $ip';
  }

  @override
  String deviceLastUsed(String time) {
    return 'Last used: $time';
  }

  @override
  String deviceExpires(String time) {
    return 'Expires: $time';
  }

  @override
  String get revokeDevice => 'Revoke device';

  @override
  String get revokeCurrentDevice => 'Sign out this device';

  @override
  String get revokeDeviceConfirmation =>
      'After revocation, this device can no longer refresh its sign-in session.';

  @override
  String get revokeCurrentDeviceConfirmation =>
      'After signing out this device, enter your username and password again to reconnect.';

  @override
  String get deviceRevoked => 'Sign-in device revoked';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

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

  @override
  String get aboutAppAction => 'About';

  @override
  String get aboutAppTitle => 'About OpenLogTool';

  @override
  String get aboutAppTagline => 'Amateur-radio net logging and collaboration';

  @override
  String get aboutAppDescription =>
      'Complete net logging, live-draft collaboration, and controller displays for on-site and remote scribes. OpenLogTool focuses on net-control workflows rather than replacing a personal contact log.';

  @override
  String aboutVersionChip(String version) {
    return 'Version $version';
  }

  @override
  String get aboutVersionSection => 'Version information';

  @override
  String get aboutVersionLabel => 'App version';

  @override
  String get aboutBuildLabel => 'Build number';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutCopyVersionInfo => 'Copy version information';

  @override
  String get aboutVersionInfoCopied => 'Version information copied';

  @override
  String get aboutCheckUpdates => 'Check for updates';

  @override
  String get aboutCheckingUpdates => 'Checking…';

  @override
  String aboutUpToDate(String version) {
    return 'You’re up to date ($version)';
  }

  @override
  String get aboutUpdateAvailableTitle => 'Update available';

  @override
  String aboutUpdateAvailableMessage(
      String currentVersion, String latestVersion) {
    return 'Current version: $currentVersion\nLatest version: $latestVersion';
  }

  @override
  String get aboutOpenRelease => 'View release';

  @override
  String get aboutUpdateLater => 'Not now';

  @override
  String get aboutUpdateCheckFailed =>
      'Couldn’t check for updates. Check your connection and try again.';

  @override
  String get aboutProjectSection => 'Project & licenses';

  @override
  String get aboutRepository => 'Project repository';

  @override
  String get aboutRepositoryHint =>
      'View source code and project documentation';

  @override
  String get aboutIssueTracker => 'Report an issue';

  @override
  String get aboutIssueTrackerHint => 'Report a bug or suggest an improvement';

  @override
  String get aboutOpenSourceLicenses => 'Open-source licenses';

  @override
  String get aboutOpenSourceLicensesHint =>
      'Review licenses for third-party components';

  @override
  String get aboutLicenseName => 'GNU AGPL-3.0';

  @override
  String get aboutLicenseHint => 'OpenLogTool is free and open-source software';

  @override
  String get aboutCopyright => '© 2026 Mazha0309 · BG5CRL';

  @override
  String aboutLinkOpenFailed(String error) {
    return 'Could not open the link: $error';
  }

  @override
  String get restoreDefaultSettings => 'Restore default settings';
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
  String get startNewRecord => 'Start new record';

  @override
  String get newRecordName => 'New record name';

  @override
  String get newRecordNameHint => 'Enter a name for this record (optional)';

  @override
  String get automaticName => 'automatic name';

  @override
  String newRecordStarted(String name) {
    return 'Started new record: $name';
  }

  @override
  String createNewRecordFailed(String error) {
    return 'Could not create a new record: $error';
  }

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
  String get openLiveShare => 'Live Share';

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
      'View and switch to past net sessions. Closed sessions open read-only.';

  @override
  String get historySessionsEmpty => 'There are no past sessions';

  @override
  String historySessionsLoadFailed(String error) {
    return 'Could not load session history: $error';
  }

  @override
  String get historySessionOpen => 'Open session';

  @override
  String get historySessionCurrent => 'Current session';

  @override
  String historySessionSwitched(String title) {
    return 'Opened session: $title';
  }

  @override
  String historySessionOpenFailed(String error) {
    return 'Could not open session: $error';
  }

  @override
  String get historySessionCloseTitle => 'Close session';

  @override
  String historySessionCloseConfirmation(String title) {
    return 'Close “$title”? It will remain available read-only in Session history.';
  }

  @override
  String get historySessionClosed => 'Session closed';

  @override
  String historySessionCloseFailed(String error) {
    return 'Could not close session: $error';
  }

  @override
  String get historySessionReopenAction => 'Reactivate';

  @override
  String get historySessionReopenTitle => 'Reactivate local session';

  @override
  String historySessionReopenConfirmation(String title) {
    return 'Reactivate “$title” and switch to it? Any other active local session will be closed automatically; collaboration sessions are not affected. Reopen a collaboration target from Collaboration & members.';
  }

  @override
  String historySessionReopened(String title) {
    return 'Reactivated and switched to session: $title';
  }

  @override
  String historySessionReopenFailed(String error) {
    return 'Could not reactivate local session: $error';
  }

  @override
  String historySessionReopenedLogsUnavailable(String title) {
    return 'Session “$title” was reactivated, but its logs could not be loaded. It is temporarily read-only; retry loading.';
  }

  @override
  String get historySessionCollaborationReopenRequired =>
      'This is a collaboration session. Open it first, then reopen it from Collaboration & members.';

  @override
  String get historySessionDeleteTitle => 'Permanently delete local session';

  @override
  String historySessionDeleteWarning(String title) {
    return 'This permanently deletes all local logs and the local collaboration replica for “$title”. This cannot be undone, but it will not delete or close the shared session on the server. Enter the full session name to confirm:';
  }

  @override
  String get historySessionDeleteNameLabel => 'Full session name';

  @override
  String get historySessionDeleteAction => 'Delete local data permanently';

  @override
  String get historySessionDeleted => 'Local session permanently deleted';

  @override
  String historySessionDeleteFailed(String error) {
    return 'Could not permanently delete local session: $error';
  }

  @override
  String get historySessionReadOnly =>
      'This is a closed historical session. Existing records are read-only.';

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
  String get logTimeInvalid => 'Enter a valid time (HH:mm)';

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
  String get convertCollaborationToLocal =>
      'Stop collaboration on this device and convert to a local session';

  @override
  String get convertCollaborationToLocalTitle =>
      'Stop collaboration on this device?';

  @override
  String convertCollaborationToLocalConfirmation(String title) {
    return 'This stops collaboration synchronization for “$title” on this device and internally replaces the current session with an editable local copy. The shared server session, its members, and other devices are not affected. This cannot be undone.';
  }

  @override
  String get convertCollaborationToLocalSucceeded =>
      'Stopped collaboration on this device and converted to a local session';

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
  String get publicShareManagement => 'Live Share · public read-only page';

  @override
  String get publicShareManagementHint =>
      'Create a read-only web page for controllers, remote scribes, or observers. It can be viewed without signing in; the link secret is shown only when created.';

  @override
  String get publicShareAccessRequired =>
      'Live Share is managed by the collaboration session owner. Sign in and publish this session first, or ask the owner to create the public link.';

  @override
  String get publicShareUnsupported =>
      'This server does not provide the secure Live Share page. Upgrade or enable public sharing on the server to create one.';

  @override
  String get publicShareCreatedTitle => 'Public read-only page created';

  @override
  String get publicShareCreatedHint =>
      'Save this link now. For security, its secret cannot be retrieved again after a refresh or sign-in.';

  @override
  String get createPublicShare => 'Create public link';

  @override
  String get copyPublicShareLink => 'Copy link';

  @override
  String get openPublicShare => 'Open in browser';

  @override
  String get revokePublicShare => 'Revoke';

  @override
  String get publicShareLinkCopied => 'Public link copied';

  @override
  String get publicShareNoActiveLinks =>
      'There are no active public links. Create one for a controller or remote observer.';

  @override
  String get publicShareSecretUnavailable =>
      'An active public link exists, but its secret was returned only when created. If it was not saved, revoke it and create a new link.';

  @override
  String get publicShareLinksTitle => 'Public link history';

  @override
  String get publicShareUnavailable => 'Revoked or expired';

  @override
  String get publicShareOpenFailed =>
      'Could not open the browser. You can still copy the link and open it manually.';

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
  String get limitWorkbenchWidthSetting => 'Limit Net Desk content width';

  @override
  String get limitWorkbenchWidthHint =>
      'Center Net Desk content and limit it to 1440 pixels on wide screens to keep fields from stretching too far.';

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
  String get serverSettingsTitle => 'Server and account';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get serverAddressHint => 'http://your-server:3000';

  @override
  String get serverSaveAndCheck => 'Save and check server';

  @override
  String serverCheckSucceeded(int min, int max) {
    return 'Connected · protocol v$min-$max';
  }

  @override
  String serverInstanceDetails(String instance, String features) {
    return 'Instance $instance\nCapabilities $features';
  }

  @override
  String get serverConnected => 'Connected';

  @override
  String get serverNotConnected => 'Not checked';

  @override
  String get serverSignedOutHint =>
      'Sign in to collaborate and manage only your own account and sign-in devices.';

  @override
  String get tokenStoragePrivateFileWarning =>
      'The system keyring is unavailable. Your sign-in is stored in a private file readable only by your Linux user and will move back to secure storage when a keyring becomes available.';

  @override
  String get tokenStorageMemoryOnlyWarning =>
      'Secure credential storage is unavailable. This sign-in lasts only while the app is running; you will need to sign in again after exiting.';

  @override
  String get serverLogin => 'Sign in';

  @override
  String get serverRegister => 'Register';

  @override
  String get serverLogout => 'Sign out';

  @override
  String serverAccountId(String id) {
    return 'Account ID: $id';
  }

  @override
  String get serverLoginSucceeded => 'Signed in to the server';

  @override
  String get serverRegistrationSucceeded => 'Registered and signed in';

  @override
  String serverLoginFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String serverRegistrationFailed(String error) {
    return 'Registration failed: $error';
  }

  @override
  String serverLogoutFailed(String error) {
    return 'Sign-out failed: $error';
  }

  @override
  String get accountChangeUsername => 'Change username';

  @override
  String get accountChangePassword => 'Change password';

  @override
  String get accountDeviceSessions => 'Sign-in devices';

  @override
  String get accountUsernameUpdated => 'Username updated';

  @override
  String accountPasswordUpdated(int count) {
    return 'Password updated. $count sign-in sessions were revoked; sign in again.';
  }

  @override
  String accountUpdateFailed(String error) {
    return 'Account action failed: $error';
  }

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameLengthHint => 'Username must be 3–64 characters';

  @override
  String get passwordLabel => 'Password';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get currentPasswordLabel => 'Current password';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get confirmNewPasswordLabel => 'Confirm new password';

  @override
  String get passwordLengthHint => 'Password must be at least 10 characters';

  @override
  String get passwordMismatch => 'The new passwords do not match';

  @override
  String get passwordChangeRequiredTitle =>
      'Temporary password must be changed';

  @override
  String passwordChangeRequiredHint(String username) {
    return 'Account $username signed in with a temporary password. Set a new password to continue.';
  }

  @override
  String passwordChangeCredentialExpires(int seconds) {
    return 'This password-change credential expires in $seconds seconds.';
  }

  @override
  String get completePasswordChange => 'Set password and sign in';

  @override
  String get cancelLogin => 'Cancel sign-in';

  @override
  String get passwordChangeCompleted =>
      'Password updated and sign-in completed';

  @override
  String get deviceSessionsTitle => 'Sign-in devices';

  @override
  String get deviceSessionsEmpty => 'There are no active sign-in devices';

  @override
  String get deviceUnknown => 'Unnamed device';

  @override
  String get deviceCurrent => 'Current device';

  @override
  String deviceIp(String ip) {
    return 'IP: $ip';
  }

  @override
  String deviceLastUsed(String time) {
    return 'Last used: $time';
  }

  @override
  String deviceExpires(String time) {
    return 'Expires: $time';
  }

  @override
  String get revokeDevice => 'Revoke device';

  @override
  String get revokeCurrentDevice => 'Sign out this device';

  @override
  String get revokeDeviceConfirmation =>
      'After revocation, this device can no longer refresh its sign-in session.';

  @override
  String get revokeCurrentDeviceConfirmation =>
      'After signing out this device, enter your username and password again to reconnect.';

  @override
  String get deviceRevoked => 'Sign-in device revoked';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

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
