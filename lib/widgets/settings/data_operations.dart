import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';

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
    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '数据操作',
              style: TextStyle(
                fontSize: isNarrow ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildTile(Icons.storage, '数据库状态', '查看数据库详细信息和日志',
                onViewDatabaseLog),
            _buildTile(Icons.message_outlined, '查看弹窗日志',
                '查看本次运行期间记录的底部弹窗消息', onViewSnackbarLog),
            _buildTile(Icons.upload, '导出数据库', '将数据库导出为JSON文件',
                onExportDatabase),
            _buildTile(Icons.download, '导入数据库', '从JSON文件导入数据库',
                onImportDatabase,
                textColor: Colors.orange),
            const Divider(),
            _buildTile(Icons.delete_forever, '清空所有数据',
                '删除所有点名记录和词典数据', onClearAllData,
                textColor: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(IconData icon, String title, String subtitle,
      VoidCallback onTap,
      {Color? textColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: textColor ?? Colors.grey[700]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 15, color: textColor)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: textColor ?? Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
