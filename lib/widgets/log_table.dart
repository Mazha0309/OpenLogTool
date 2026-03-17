import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';

/// 日志表格组件
/// 用于显示已有的点名记录
class LogTable extends StatelessWidget {
  const LogTable({super.key});

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);

    if (logProvider.logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.list_alt,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无点名记录',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请在上方表单中添加第一条记录',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    // 使用 Scrollbar 包裹实现横向滚动条
    return Scrollbar(
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 16,
            horizontalMargin: 16,
            headingRowHeight: 48,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 64,
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
            dataTextStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
            border: TableBorder.all(
              color: Theme.of(context).dividerColor,
              width: 1,
              borderRadius: BorderRadius.circular(8),
            ),
            columns: const [
              DataColumn(
                label: SizedBox(width: 60, child: Text('#')),
              ),
              DataColumn(
                label: SizedBox(width: 100, child: Text('时间')),
              ),
              DataColumn(
                label: SizedBox(width: 120, child: Text('点名主控')),
              ),
              DataColumn(
                label: SizedBox(width: 120, child: Text('呼号')),
              ),
              DataColumn(
                label: SizedBox(width: 100, child: Text('信号报告')),
              ),
              DataColumn(
                label: SizedBox(width: 150, child: Text('QTH')),
              ),
              DataColumn(
                label: SizedBox(width: 150, child: Text('设备')),
              ),
              DataColumn(
                label: SizedBox(width: 80, child: Text('功率')),
              ),
              DataColumn(
                label: SizedBox(width: 150, child: Text('天线')),
              ),
              DataColumn(
                label: SizedBox(width: 80, child: Text('高度')),
              ),
              DataColumn(
                label: SizedBox(width: 120, child: Text('操作')),
              ),
            ],
            rows: logProvider.logs.asMap().entries.map((entry) {
              final index = entry.key;
              final log = entry.value;
              
              return DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 60,
                      child: Text('${index + 1}'),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 100,
                      child: Text(log.time),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(log.controller),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(log.callsign),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 100,
                      child: Text(log.report),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 150,
                      child: Text(log.qth),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 150,
                      child: Text(log.device),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 80,
                      child: Text(log.power),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 150,
                      child: Text(log.antenna),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 80,
                      child: Text(log.height),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () {
                              logProvider.startEditing(index);
                              PrimaryScrollController.of(context)?.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            tooltip: '编辑记录',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            onPressed: () => _showDeleteConfirmation(context, index),
                            tooltip: '删除记录',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmation(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).deleteLog(index);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('记录已删除'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
