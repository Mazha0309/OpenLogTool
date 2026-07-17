import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';

typedef DatabaseOperationCallback = Future<void> Function();

class DataOperations extends StatefulWidget {
  final bool isNarrow;
  final double cardPadding;
  final DatabaseOperationCallback onViewDatabaseLog;
  final DatabaseOperationCallback onExportDatabase;
  final DatabaseOperationCallback onImportDatabase;
  final DatabaseOperationCallback onViewSnackbarLog;
  final DatabaseOperationCallback onClearAllData;

  const DataOperations({
    super.key,
    required this.isNarrow,
    required this.cardPadding,
    required this.onViewDatabaseLog,
    required this.onExportDatabase,
    required this.onImportDatabase,
    required this.onViewSnackbarLog,
    required this.onClearAllData,
  });

  @override
  State<DataOperations> createState() => _DataOperationsState();
}

class _DataOperationsState extends State<DataOperations> {
  String? _activeOperation;

  Future<void> _run(
    String operation,
    DatabaseOperationCallback callback,
  ) async {
    if (_activeOperation != null) return;
    setState(() => _activeOperation = operation);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _activeOperation = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.storage_outlined,
      title: context.l10n.localDataOperationsTitle,
      description: context.l10n.localDataOperationsHint,
      padding: widget.cardPadding,
      contentSpacing: widget.isNarrow ? 10 : 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSectionLabel(context.l10n.databaseDiagnosticsSection),
          SettingsTileGroup(
            children: [
              _buildTile(
                context,
                operation: 'status',
                icon: Icons.storage_outlined,
                title: context.l10n.databaseStatusTitle,
                subtitle: context.l10n.databaseStatusHint,
                onTap: widget.onViewDatabaseLog,
              ),
              _buildTile(
                context,
                operation: 'snackbar-log',
                icon: Icons.message_outlined,
                title: context.l10n.snackbarLogTitle,
                subtitle: context.l10n.snackbarLogHint,
                onTap: widget.onViewSnackbarLog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSectionLabel(context.l10n.databaseBackupSection),
          SettingsTileGroup(
            children: [
              _buildTile(
                context,
                operation: 'export',
                icon: Icons.file_upload_outlined,
                title: context.l10n.databaseExportTitle,
                subtitle: context.l10n.databaseExportHint,
                onTap: widget.onExportDatabase,
              ),
              _buildTile(
                context,
                operation: 'import',
                icon: Icons.file_download_outlined,
                title: context.l10n.databaseImportTitle,
                subtitle: context.l10n.databaseImportHint,
                onTap: widget.onImportDatabase,
                tone: SettingsTone.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSectionLabel(
            context.l10n.databaseDangerZoneSection,
            tone: SettingsTone.danger,
          ),
          SettingsTileGroup(
            children: [
              _buildTile(
                context,
                operation: 'clear',
                icon: Icons.delete_forever_outlined,
                title: context.l10n.databaseClearTitle,
                subtitle: context.l10n.databaseClearHint,
                onTap: widget.onClearAllData,
                tone: SettingsTone.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String operation,
    required IconData icon,
    required String title,
    required String subtitle,
    required DatabaseOperationCallback onTap,
    SettingsTone tone = SettingsTone.primary,
  }) {
    final enabled = _activeOperation == null;
    final running = _activeOperation == operation;

    return SettingsActionTile(
      key: Key('database-operation-$operation'),
      icon: icon,
      title: title,
      subtitle: subtitle,
      tone: tone,
      enabled: enabled,
      busy: running,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _run(operation, onTap),
    );
  }
}
