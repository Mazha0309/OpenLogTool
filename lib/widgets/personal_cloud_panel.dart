import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';
import 'package:provider/provider.dart';

class PersonalCloudPanel extends StatelessWidget {
  const PersonalCloudPanel({
    super.key,
    this.isNarrow = false,
    this.cardPadding = AppSpace.md,
  });

  final bool isNarrow;
  final double cardPadding;

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<PersonalCloudProvider>();
    final meta = cloud.cloudMeta;
    final decision = cloud.state == PersonalCloudSyncState.decisionRequired;
    return SettingsSectionCard(
      key: const Key('personal-cloud-panel'),
      icon: Icons.cloud_sync_outlined,
      title: context.l10n.personalCloudTitle,
      description: context.l10n.personalCloudHint,
      padding: cardPadding,
      tone: decision ? SettingsTone.tertiary : SettingsTone.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppNotice(
            message: _stateLabel(context, cloud),
            icon: _stateIcon(cloud.state),
            tone: _stateTone(cloud.state),
          ),
          if (cloud.isSignedIn && cloud.isSupported) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                Text(
                  context.l10n.personalCloudLocalSummary(
                    cloud.localSessionCount,
                    cloud.localLogCount,
                  ),
                ),
                Text(
                  meta == null || !meta.exists
                      ? context.l10n.personalCloudRemoteEmpty
                      : context.l10n.personalCloudRemoteSummary(
                          meta.sessionCount,
                          meta.logCount,
                          meta.revision,
                        ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  key: const Key('personal-cloud-sync-now'),
                  onPressed: cloud.isBusy ? null : () => _sync(context, cloud),
                  icon: cloud.isBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(context.l10n.personalCloudSyncNow),
                ),
                OutlinedButton.icon(
                  key: const Key('personal-cloud-replace-remote'),
                  onPressed: cloud.isBusy ||
                          meta == null ||
                          cloud.localSnapshotToken == null
                      ? null
                      : () => _replaceRemote(context, cloud),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(context.l10n.personalCloudReplaceRemote),
                ),
                OutlinedButton.icon(
                  key: const Key('personal-cloud-restore-local'),
                  onPressed: cloud.isBusy ||
                          meta?.exists != true ||
                          cloud.localSnapshotToken == null
                      ? null
                      : () => _restoreLocal(context, cloud),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(context.l10n.personalCloudRestoreLocal),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _stateLabel(
    BuildContext context,
    PersonalCloudProvider cloud,
  ) {
    switch (cloud.state) {
      case PersonalCloudSyncState.signedOut:
        return context.l10n.personalCloudSignedOut;
      case PersonalCloudSyncState.unsupported:
        return context.l10n.personalCloudUnsupported;
      case PersonalCloudSyncState.checking:
        return context.l10n.personalCloudChecking;
      case PersonalCloudSyncState.syncing:
        return context.l10n.personalCloudSyncing;
      case PersonalCloudSyncState.upToDate:
        return context.l10n.personalCloudUpToDate;
      case PersonalCloudSyncState.decisionRequired:
        return context.l10n.personalCloudDecisionRequired;
      case PersonalCloudSyncState.error:
        return context.l10n.personalCloudError(
          cloud.lastError ?? 'UNKNOWN_ERROR',
        );
    }
  }

  static IconData _stateIcon(PersonalCloudSyncState state) => switch (state) {
        PersonalCloudSyncState.signedOut => Icons.cloud_off_outlined,
        PersonalCloudSyncState.unsupported => Icons.cloud_off_outlined,
        PersonalCloudSyncState.checking => Icons.manage_search_outlined,
        PersonalCloudSyncState.syncing => Icons.sync,
        PersonalCloudSyncState.upToDate => Icons.cloud_done_outlined,
        PersonalCloudSyncState.decisionRequired => Icons.compare_arrows,
        PersonalCloudSyncState.error => Icons.cloud_off_outlined,
      };

  static AppTone _stateTone(PersonalCloudSyncState state) => switch (state) {
        PersonalCloudSyncState.upToDate => AppTone.success,
        PersonalCloudSyncState.decisionRequired => AppTone.warning,
        PersonalCloudSyncState.error => AppTone.danger,
        _ => AppTone.neutral,
      };

  static Future<void> _sync(
    BuildContext context,
    PersonalCloudProvider cloud,
  ) async {
    try {
      await cloud.syncNow();
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudError('$error'))),
      );
    }
  }

  static Future<void> _replaceRemote(
    BuildContext context,
    PersonalCloudProvider cloud,
  ) async {
    final meta = cloud.cloudMeta;
    final localToken = cloud.localSnapshotToken;
    if (meta == null || localToken == null) return;
    final confirmed = await _showTypedConfirmation(
      context,
      title: context.l10n.personalCloudReplaceTitle,
      warning: context.l10n.personalCloudReplaceWarning(
        cloud.localSessionCount,
        cloud.localLogCount,
        meta.sessionCount,
        meta.logCount,
      ),
      phrase: context.l10n.personalCloudReplacePhrase,
      action: context.l10n.personalCloudReplaceAction,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await cloud.replaceCloudWithLocal(
        expectedCloudRevision: meta.revision,
        expectedLocalSnapshotToken: localToken,
      );
      if (cloud.state != PersonalCloudSyncState.upToDate) return;
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudReplaceSucceeded)),
      );
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudError('$error'))),
      );
    }
  }

  static Future<void> _restoreLocal(
    BuildContext context,
    PersonalCloudProvider cloud,
  ) async {
    final meta = cloud.cloudMeta;
    final localToken = cloud.localSnapshotToken;
    if (meta == null || !meta.exists || localToken == null) return;
    final confirmed = await _showTypedConfirmation(
      context,
      title: context.l10n.personalCloudRestoreTitle,
      warning: context.l10n.personalCloudRestoreWarning(
        meta.sessionCount,
        meta.logCount,
        cloud.localSessionCount,
        cloud.localLogCount,
      ),
      phrase: context.l10n.personalCloudRestorePhrase,
      action: context.l10n.personalCloudRestoreAction,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await cloud.restoreCloudToLocal(
        expectedCloudRevision: meta.revision,
        expectedLocalSnapshotToken: localToken,
      );
      if (cloud.state != PersonalCloudSyncState.upToDate) return;
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudRestoreSucceeded)),
      );
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(content: Text(context.l10n.personalCloudError('$error'))),
      );
    }
  }

  static Future<bool?> _showTypedConfirmation(
    BuildContext context, {
    required String title,
    required String warning,
    required String phrase,
    required String action,
  }) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: AppDimensions.dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNotice(
                  message: warning,
                  icon: Icons.warning_amber_rounded,
                  tone: AppTone.danger,
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  dialogContext.l10n.databaseClearConfirmationInstruction(
                    phrase,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        dialogContext.l10n.databaseClearConfirmationLabel,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: controller.text == phrase
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(action),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }
}
