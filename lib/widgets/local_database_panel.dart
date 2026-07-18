import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/database_backup_summary.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/personal_cloud_panel.dart';
import 'package:openlogtool/widgets/settings/data_operations.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';
import 'package:provider/provider.dart';

/// Reusable on-device database management surface.
///
/// The data center owns where this panel is placed. Keeping the complete
/// maintenance workflow here prevents settings and data pages from each
/// growing a subtly different set of import, backup and reset dialogs.
class LocalDatabasePanel extends StatelessWidget {
  static const _nativeFileDialog = MethodChannel(
    'com.mazha0309.openlogtool/native_file_dialog',
  );

  const LocalDatabasePanel({
    super.key,
    this.isNarrow = false,
    this.cardPadding = AppSpace.md,
  });

  final bool isNarrow;
  final double cardPadding;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalCloudPanel(
            isNarrow: isNarrow,
            cardPadding: cardPadding,
          ),
          const SizedBox(height: AppSpace.md),
          DataOperations(
            isNarrow: isNarrow,
            cardPadding: cardPadding,
            onViewDatabaseLog: () => _showDatabaseLogDialog(context),
            onExportDatabase: () => _exportDatabase(context),
            onImportDatabase: () => _importDatabase(context),
            onViewSnackbarLog: () => _showSnackbarLogDialog(context),
            onClearAllData: () => _showClearDataConfirmation(context),
          ),
        ],
      );

  Future<void> _showSnackbarLogDialog(BuildContext context) async {
    final entries = context.read<SnackbarLogProvider>().entries;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: _dialogInsetPadding(dialogContext),
        title: Text(dialogContext.l10n.snackbarLogTitle),
        content: SizedBox(
          width: AppDimensions.dialogWidth,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: entries.isEmpty
                ? Text(dialogContext.l10n.snackbarLogEmpty)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: AppSpace.md),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpace.xxs),
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
        // Mobile document providers write supplied bytes. Desktop pickers only
        // select a path (macOS rejects a bytes argument).
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
          content: Text(context.l10n.databaseExportFailed(error.toString())),
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
      final pickedFile = await _pickDatabaseBackup(context);
      if (pickedFile == null) {
        if (!context.mounted) return;
        context.showLoggedSnackBar(
          SnackBar(
            content: Text(context.l10n.databaseImportNoFileSelected),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      selectedFile = pickedFile;
      jsonData = await _readSelectedBackup(selectedFile);
      summary = DatabaseBackupSummary.parse(jsonData);
    } on FormatException catch (error) {
      if (!context.mounted) return;
      context.showLoggedSnackBar(
        SnackBar(
          content: Text(context.l10n.databaseImportInvalid(error.message)),
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
      successMessage: (l10n) => l10n.databaseImportSucceededSummary(
        summary.sessionCount,
        summary.logCount,
      ),
      failureMessage: (l10n, error) =>
          l10n.databaseImportFailed(_friendlyDatabaseError(l10n, error)),
    );
  }

  Future<PlatformFile?> _pickDatabaseBackup(BuildContext context) async {
    final dialogTitle = context.l10n.databaseImportPickerTitle;
    // file_picker shells out to zenity on Linux. That path can lose its result
    // under Wayland compositors when the portal cannot associate the external
    // dialog with the Flutter window. The runner owns a GTK chooser so Linux
    // keeps the dialog and its parent inside this process.
    if (!kIsWeb && Platform.isLinux) {
      try {
        final path = await _nativeFileDialog.invokeMethod<String>(
          'pickJsonBackup',
          {'title': dialogTitle},
        );
        if (path == null || path.trim().isEmpty) return null;
        final normalizedPath = path.trim();
        final file = File(normalizedPath);
        return PlatformFile(
          name: normalizedPath
              .split(Platform.pathSeparator)
              .where((segment) => segment.isNotEmpty)
              .last,
          path: normalizedPath,
          size: await file.length(),
        );
      } on MissingPluginException {
        // Keep debug/test runners and older custom Linux embeddings usable.
      }
    }

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
      withReadStream: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single;
  }

  Future<bool?> _showImportConfirmation(
    BuildContext context, {
    required String fileName,
    required DatabaseBackupSummary summary,
  }) =>
      showDialog<bool>(
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
                  const SizedBox(height: AppSpace.sm),
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
                  const SizedBox(height: AppSpace.sm),
                  AppNotice(
                    message: l10n.databaseImportPreviewWarning,
                    icon: Icons.warning_amber_rounded,
                    tone: AppTone.danger,
                  ),
                  if (summary.containsCollaborationData) ...[
                    const SizedBox(height: AppSpace.sm),
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
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
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
          width: AppDimensions.dialogWidth,
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

  static EdgeInsets _dialogInsetPadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.compact
          ? const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.lg,
            )
          : const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: AppSpace.lg,
            );

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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
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
            const SizedBox(width: AppSpace.md),
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

class _ClearDatabaseConfirmationDialog extends StatefulWidget {
  const _ClearDatabaseConfirmationDialog({required this.confirmationPhrase});

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
        insetPadding: MediaQuery.sizeOf(context).width < AppBreakpoints.compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.lg,
              )
            : const EdgeInsets.symmetric(
                horizontal: 40,
                vertical: AppSpace.lg,
              ),
        scrollable: true,
        title: Text(context.l10n.databaseClearTitle),
        content: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppNotice(
                message: context.l10n.databaseClearWarning,
                icon: Icons.warning_amber_rounded,
                tone: AppTone.danger,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                context.l10n.databaseClearConfirmationInstruction(
                  widget.confirmationPhrase,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                key: const Key('database-clear-confirmation-field'),
                controller: _controller,
                decoration: InputDecoration(
                  labelText: context.l10n.databaseClearConfirmationLabel,
                  hintText: widget.confirmationPhrase,
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
