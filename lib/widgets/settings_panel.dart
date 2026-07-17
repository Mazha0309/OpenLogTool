import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/database_backup_summary.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/about_app_dialog.dart';
import 'package:openlogtool/widgets/font_picker_dialog.dart';
import 'package:openlogtool/widgets/settings/controller_display_settings.dart';
import 'package:openlogtool/widgets/settings/data_operations.dart';
import 'package:openlogtool/widgets/settings/layout_settings.dart';
import 'package:openlogtool/widgets/settings/server_account_settings.dart';
import 'package:openlogtool/widgets/settings/theme_settings.dart';
import 'package:openlogtool/widgets/theme_color_picker_dialog.dart';
import 'package:provider/provider.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appInfoProvider = Provider.of<AppInfoProvider>(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 860;
      final cardPadding = constraints.maxWidth < 600 ? 12.0 : 16.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.settingsTitle,
            style: TextStyle(
              fontSize: isNarrow ? 18 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: isNarrow ? 16 : 24),
          if (isNarrow) ...[
            ThemeSettings(
              isNarrow: constraints.maxWidth < 600,
              cardPadding: cardPadding,
              onPickColor: () => _showColorPicker(context),
              onPickFont: () => _showFontPicker(context),
            ),
            const SizedBox(height: 16),
            LayoutSettings(
              isNarrow: constraints.maxWidth < 600,
              cardPadding: cardPadding,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ThemeSettings(
                    isNarrow: false,
                    cardPadding: cardPadding,
                    onPickColor: () => _showColorPicker(context),
                    onPickFont: () => _showFontPicker(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LayoutSettings(
                    isNarrow: false,
                    cardPadding: cardPadding,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          ControllerDisplaySettings(cardPadding: cardPadding),
          const SizedBox(height: 16),
          ServerAccountSettings(cardPadding: cardPadding),
          const SizedBox(height: 16),
          DataOperations(
            isNarrow: isNarrow,
            cardPadding: cardPadding,
            onViewDatabaseLog: () => _showDatabaseLogDialog(context),
            onExportDatabase: () => _exportDatabase(context),
            onImportDatabase: () => _importDatabase(context),
            onViewSnackbarLog: () => _showSnackbarLogDialog(context),
            onClearAllData: () => _showClearDataConfirmation(context),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: ListTile(
              key: const Key('about-app-entry'),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: cardPadding, vertical: 6),
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                context.l10n.aboutAppTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${context.l10n.aboutAppTagline}\n'
                '${appInfoProvider.fullVersion} · '
                '${context.l10n.aboutLicenseName}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAboutDialog(context),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showResetConfirmation(context),
              icon: const Icon(Icons.restore_outlined),
              label: Text(context.l10n.restoreDefaultSettings),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _showSnackbarLogDialog(BuildContext context) async {
    final entries = context.read<SnackbarLogProvider>().entries;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: _dialogInsetPadding(dialogContext),
        title: Text(dialogContext.l10n.snackbarLogTitle),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: entries.isEmpty
                ? Text(dialogContext.l10n.snackbarLogEmpty)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final time =
                          '${entry.createdAt.hour.toString().padLeft(2, '0')}:'
                          '${entry.createdAt.minute.toString().padLeft(2, '0')}:'
                          '${entry.createdAt.second.toString().padLeft(2, '0')}';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            entry.message,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$time · ${entry.type} · ${entry.source}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorPickerDialog(
        initialColor: settingsProvider.themeColor,
      ),
    );
    if (selectedColor != null) {
      await settingsProvider.setThemeColor(selectedColor);
    }
  }

  Future<void> _showResetConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: _dialogInsetPadding(dialogContext),
        scrollable: true,
        title: Text(dialogContext.l10n.resetSettingsTitle),
        content: Text(dialogContext.l10n.resetSettingsConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.resetSettingsConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await context.read<SettingsProvider>().resetToDefaults();
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(context.l10n.resetSettingsSucceeded),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(context.l10n.resetSettingsFailed(error.toString())),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showClearDataConfirmation(BuildContext context) async {
    final phrase = context.l10n.databaseClearConfirmationPhrase;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ClearDatabaseConfirmationDialog(
        confirmationPhrase: phrase,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _replaceLocalDatabase(
      context,
      replacement: RustApi.clearAllData,
      successMessage: (l10n) => l10n.databaseClearSucceeded,
      failureMessage: (l10n, error) =>
          l10n.databaseClearFailed(_friendlyDatabaseError(l10n, error)),
    );
  }

  Future<void> _exportDatabase(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final jsonData = await RustApi.exportDatabase();
      final encodedBackup = utf8.encode(jsonData);
      final pickerWritesBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;
      final now = DateTime.now();
      final fileName = 'openlogtool_backup_${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.json';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: l10n.databaseExportDialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        // Mobile document providers require bytes and write them themselves.
        // Desktop pickers only select a path (macOS rejects a bytes argument).
        bytes: pickerWritesBytes ? encodedBackup : null,
      );
      if (result == null) return;

      if (!pickerWritesBytes) {
        await File(result).writeAsString(jsonData, flush: true);
      }

      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(context.l10n.databaseExportSucceeded),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(
            context.l10n.databaseExportFailed(error.toString()),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _importDatabase(BuildContext context) async {
    final PlatformFile selectedFile;
    final String jsonData;
    final DatabaseBackupSummary summary;
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: context.l10n.databaseImportPickerTitle,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        // Native platforms expose a temporary/local path. On web a stream
        // avoids keeping both a byte buffer and the decoded JSON in memory.
        withData: false,
        withReadStream: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      selectedFile = result.files.single;
      jsonData = await _readSelectedBackup(selectedFile);
      summary = DatabaseBackupSummary.parse(jsonData);
    } on FormatException catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(
            context.l10n.databaseImportInvalid(error.message),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    } catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(
            context.l10n.databaseImportReadFailed(error.toString()),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final confirmed = await _showImportConfirmation(
      context,
      fileName: selectedFile.name,
      summary: summary,
    );
    if (confirmed != true || !context.mounted) return;

    await _replaceLocalDatabase(
      context,
      replacement: () => RustApi.importDatabase(jsonData: jsonData),
      successMessage: (l10n) => l10n.databaseImportSucceeded,
      failureMessage: (l10n, error) =>
          l10n.databaseImportFailed(_friendlyDatabaseError(l10n, error)),
    );
  }

  Future<bool?> _showImportConfirmation(
    BuildContext context, {
    required String fileName,
    required DatabaseBackupSummary summary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        final exportedAt = summary.exportedAt == null
            ? l10n.databaseImportUnknownTime
            : _formatLocalDateTime(dialogContext, summary.exportedAt!);
        return AlertDialog(
          insetPadding: _dialogInsetPadding(dialogContext),
          scrollable: true,
          title: Text(l10n.databaseImportPreviewTitle),
          content: SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                _BackupSummaryRow(
                  label: l10n.databaseImportBackupVersion,
                  value: summary.formatVersion.toString(),
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportExportedAt,
                  value: exportedAt,
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportSessionCount,
                  value: summary.sessionCount.toString(),
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportLogCount,
                  value: summary.logCount.toString(),
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportDictionaryCount,
                  value: summary.dictionaryItemCount.toString(),
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportCollaborationCount,
                  value: summary.collaborationBindingCount.toString(),
                ),
                _BackupSummaryRow(
                  label: l10n.databaseImportPendingSyncCount,
                  value: summary.pendingSyncCount.toString(),
                ),
                const SizedBox(height: 12),
                _DangerNotice(message: l10n.databaseImportPreviewWarning),
                if (summary.containsCollaborationData) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.databaseImportCollaborationWarning,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('database-import-confirm-action'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.databaseImportConfirmAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _replaceLocalDatabase(
    BuildContext context, {
    required Future<void> Function() replacement,
    required String Function(AppLocalizations l10n) successMessage,
    required String Function(AppLocalizations l10n, Object error)
        failureMessage,
  }) async {
    final collaboration = context.read<CollaborationProvider>();
    final dictionaries = context.read<DictionaryProvider>();
    var databaseCommitted = false;
    try {
      await collaboration.runLocalDatabaseMaintenance(() async {
        await replacement();
        databaseCommitted = true;
      });
      // CollaborationProvider has already rebuilt SessionProvider/LogProvider
      // while synchronization was stopped. Dictionaries are independent of
      // the collaboration replica and are refreshed immediately afterwards.
      await dictionaries.reloadFromDatabase(
        synchronizeBuiltins: true,
        strictBuiltinSynchronization: true,
      );

      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(successMessage(context.l10n)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = databaseCommitted
          ? context.l10n.databaseReplacementRefreshFailed
          : failureMessage(context.l10n, error);
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _showDatabaseLogDialog(BuildContext context) async {
    final status = await _buildDatabaseStatus(context);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: _dialogInsetPadding(dialogContext),
        title: Text(dialogContext.l10n.databaseStatusTitle),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(
                status,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<String> _buildDatabaseStatus(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final raw = await RustApi.getDatabaseStatus();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['tables'] is! List) {
        return raw;
      }
      final buffer = StringBuffer();
      final schemaVersion = decoded['schemaVersion'];
      buffer.writeln(
        l10n.databaseStatusSchemaVersion(
          schemaVersion?.toString() ?? l10n.databaseStatusUnknown,
        ),
      );
      buffer.writeln();
      for (final table in decoded['tables'] as List) {
        if (table is! Map) continue;
        final name = table['name']?.toString();
        final count = table['rowCount'];
        if (name == null || count is! num) continue;
        buffer.writeln(l10n.databaseStatusTableRow(name, count.toInt()));
      }
      return buffer.toString().trimRight();
    } catch (error) {
      return l10n.databaseStatusLoadFailed(error.toString());
    }
  }

  void _showAboutDialog(BuildContext context) {
    final appInfoProvider = context.read<AppInfoProvider>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AboutAppDialog(
        appName: appInfoProvider.appName,
        fullVersion: appInfoProvider.fullVersion,
        buildNumber: appInfoProvider.buildNumber,
        commitHash: appInfoProvider.commitHash,
      ),
    );
  }

  Future<void> _showFontPicker(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final result = await showDialog<FontPickerResult>(
      context: context,
      // A global font change rebuilds the whole app. Keeping this route
      // transition-free ensures the picker is fully gone before that rebuild
      // starts, instead of competing with the dialog's exit animation.
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => FontPickerDialog(
        availableFonts: settingsProvider.availableFonts,
        currentFont: settingsProvider.fontFamily,
      ),
    );
    if (result == null || !context.mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    await settingsProvider.setFontFamily(result.fontFamily);
  }

  static Future<String> _readSelectedBackup(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return utf8.decode(bytes);
    final stream = file.readStream;
    if (stream != null) return utf8.decoder.bind(stream).join();
    final path = file.path;
    if (path != null && path.isNotEmpty && !kIsWeb) {
      return File(path).readAsString();
    }
    throw StateError('DATABASE_BACKUP_FILE_UNAVAILABLE');
  }

  static String _formatLocalDateTime(BuildContext context, DateTime value) {
    final material = MaterialLocalizations.of(context);
    return '${material.formatFullDate(value)} '
        '${material.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: true,
    )}';
  }

  static EdgeInsets _dialogInsetPadding(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  }

  static String _friendlyDatabaseError(
    AppLocalizations l10n,
    Object error,
  ) {
    final raw = error.toString();
    if (raw.contains('COLLABORATION_OPERATION_IN_PROGRESS')) {
      return l10n.databaseMaintenanceCollaborationBusy;
    }
    if (raw.contains('DATABASE_BACKUP_')) {
      return l10n.databaseImportInvalid(raw);
    }
    return raw;
  }
}

class _BackupSummaryRow extends StatelessWidget {
  const _BackupSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClearDatabaseConfirmationDialog extends StatefulWidget {
  const _ClearDatabaseConfirmationDialog({
    required this.confirmationPhrase,
  });

  final String confirmationPhrase;

  @override
  State<_ClearDatabaseConfirmationDialog> createState() =>
      _ClearDatabaseConfirmationDialogState();
}

class _ClearDatabaseConfirmationDialogState
    extends State<_ClearDatabaseConfirmationDialog> {
  final _controller = TextEditingController();
  bool _phraseMatches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        insetPadding: MediaQuery.sizeOf(context).width < 600
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        scrollable: true,
        title: Text(context.l10n.databaseClearTitle),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DangerNotice(message: context.l10n.databaseClearWarning),
              const SizedBox(height: 16),
              Text(
                context.l10n.databaseClearConfirmationInstruction(
                  widget.confirmationPhrase,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('database-clear-confirmation-field'),
                controller: _controller,
                decoration: InputDecoration(
                  labelText: context.l10n.databaseClearConfirmationLabel,
                  hintText: widget.confirmationPhrase,
                  border: const OutlineInputBorder(),
                ),
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (value) {
                  final matches = value.trim() == widget.confirmationPhrase;
                  if (matches != _phraseMatches) {
                    setState(() => _phraseMatches = matches);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('database-clear-confirm-action'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed:
                _phraseMatches ? () => Navigator.pop(context, true) : null,
            child: Text(context.l10n.databaseClearConfirmAction),
          ),
        ],
      );
}

class _DangerNotice extends StatelessWidget {
  const _DangerNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
