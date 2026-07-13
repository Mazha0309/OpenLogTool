import 'package:flutter/material.dart';

class DataOperations extends StatelessWidget {
  final bool isNarrow;
  final double cardPadding;
  final VoidCallback onViewDatabaseLog;
  final VoidCallback onExportDatabase;
  final VoidCallback onImportDatabase;
  final VoidCallback onViewSnackbarLog;
  final VoidCallback onClearAllData;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '数据操作',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildTile(
              context,
              icon: Icons.storage,
              title: '数据库状态',
              subtitle: '查看数据库表结构和行数统计',
              onTap: onViewDatabaseLog,
            ),
            _buildTile(
              context,
              icon: Icons.message_outlined,
              title: '查看弹窗日志',
              subtitle: '查看本次运行期间记录的底部弹窗消息',
              onTap: onViewSnackbarLog,
            ),
            _buildTile(
              context,
              icon: Icons.upload,
              title: '导出数据库',
              subtitle: '将数据库导出为 JSON 备份文件',
              onTap: onExportDatabase,
            ),
            _buildTile(
              context,
              icon: Icons.download,
              title: '导入数据库',
              subtitle: '从 JSON 备份文件导入并覆盖现有数据',
              onTap: onImportDatabase,
              textColor: Colors.orange,
            ),
            const Divider(),
            _buildTile(
              context,
              icon: Icons.delete_forever,
              title: '清空所有数据',
              subtitle: '删除所有点名记录和词库数据，不可恢复',
              onTap: onClearAllData,
              textColor: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (textColor ?? theme.colorScheme.primary).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: textColor ?? theme.colorScheme.primary,
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
                      color: textColor,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor != null
                            ? textColor.withAlpha(180)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
