import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';

class LogTable extends StatelessWidget {
  const LogTable({super.key});

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);

    if (logProvider.logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        horizontalMargin: 0,
        headingRowHeight: 48,
        dataRowHeight: 56,
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        dataTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('时间')),
          DataColumn(label: Text('点名主控')),
          DataColumn(label: Text('呼号')),
          DataColumn(label: Text('信号报告')),
          DataColumn(label: Text('QTH')),
          DataColumn(label: Text('设备')),
          DataColumn(label: Text('功率')),
          DataColumn(label: Text('天线')),
          DataColumn(label: Text('高度')),
          DataColumn(label: Text('操作')),
        ],
        rows: logProvider.logs.asMap().entries.map((entry) {
          final index = entry.key;
          final log = entry.value;
          
          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(log.time)),
              DataCell(Text(log.controller)),
              DataCell(Text(log.callsign)),
              DataCell(Text(log.report)),
              DataCell(Text(log.qth)),
              DataCell(Text(log.device)),
              DataCell(Text(log.power)),
              DataCell(Text(log.antenna)),
              DataCell(Text(log.height)),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () {
                        logProvider.startEditing(index);
                        // 滚动到顶部
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
                            .withOpacity(0.1),
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
                            .withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

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