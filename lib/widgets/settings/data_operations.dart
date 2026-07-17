import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';

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
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(128),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.localDataOperationsTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.localDataOperationsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: widget.isNarrow ? 8 : 12),
            _buildSectionLabel(
                context, context.l10n.databaseDiagnosticsSection),
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
            const Divider(height: 24),
            _buildSectionLabel(context, context.l10n.databaseBackupSection),
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
              textColor: theme.colorScheme.tertiary,
            ),
            const Divider(height: 24),
            _buildSectionLabel(
              context,
              context.l10n.databaseDangerZoneSection,
              color: theme.colorScheme.error,
            ),
            _buildTile(
              context,
              operation: 'clear',
              icon: Icons.delete_forever_outlined,
              title: context.l10n.databaseClearTitle,
              subtitle: context.l10n.databaseClearHint,
              onTap: widget.onClearAllData,
              textColor: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(
    BuildContext context,
    String label, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
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
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final enabled = _activeOperation == null;
    final running = _activeOperation == operation;
    final effectiveColor = textColor ?? theme.colorScheme.primary;

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        key: Key('database-operation-$operation'),
        onTap: enabled ? () => _run(operation, onTap) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: effectiveColor.withAlpha(enabled ? 20 : 10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: enabled ? effectiveColor : theme.disabledColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: enabled ? textColor : theme.disabledColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? (textColor != null
                                ? textColor.withAlpha(190)
                                : theme.colorScheme.onSurfaceVariant)
                            : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (running)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
