import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

class LogTable extends StatefulWidget {
  const LogTable({super.key});

  @override
  State<LogTable> createState() => _LogTableState();
}

class _LogTableState extends State<LogTable> {
  int? _editingIndex;
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _startEditing(int index, LogEntry log) {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.startEditing(index);
    setState(() {
      _editingIndex = index;
      _controllers = {
        'time': TextEditingController(text: log.time),
        'controller': TextEditingController(text: log.controller),
        'callsign': TextEditingController(text: log.callsign),
        'report': TextEditingController(text: log.report),
        'qth': TextEditingController(text: log.qth),
        'device': TextEditingController(text: log.device),
        'power': TextEditingController(text: log.power),
        'antenna': TextEditingController(text: log.antenna),
        'height': TextEditingController(text: log.height),
      };
    });
  }

  void _cancelEditing() {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.cancelEditing();
    setState(() {
      _editingIndex = null;
      for (var controller in _controllers.values) {
        controller.dispose();
      }
      _controllers = {};
    });
  }

  Future<void> _saveEditing(int index) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final updatedLog = LogEntry(
      time: _controllers['time']?.text ?? '',
      controller: _controllers['controller']?.text ?? '',
      callsign: _controllers['callsign']?.text ?? '',
      report: _controllers['report']?.text ?? '',
      qth: _controllers['qth']?.text ?? '',
      device: _controllers['device']?.text ?? '',
      power: _controllers['power']?.text ?? '',
      antenna: _controllers['antenna']?.text ?? '',
      height: _controllers['height']?.text ?? '',
    );
    logProvider.updateLog(index, updatedLog);
    _cancelEditing();
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);

    if (logProvider.logs.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

    final horizontalController = ScrollController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 8),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.history, size: 18),
            label: const Text('历史记录'),
            onPressed: () => _showHistoryDialog(context),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) => true,
            child: Scrollbar(
              controller: horizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: horizontalController,
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
                      final isEditing = _editingIndex == index;

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
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['time'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.time),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['controller'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.controller),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['callsign'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.callsign),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 100,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['report'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.report),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['qth'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.qth),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['device'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.device),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 80,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['power'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.power),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['antenna'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.antenna),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 80,
                              child: isEditing
                                  ? TextField(
                                      controller: _controllers['height'],
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      ),
                                    )
                                  : Text(log.height),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: isEditing
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.check, size: 20),
                                          onPressed: () => _saveEditing(index),
                                          tooltip: '保存',
                                          style: IconButton.styleFrom(
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.1),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.close, size: 20),
                                          onPressed: _cancelEditing,
                                          tooltip: '取消',
                                          style: IconButton.styleFrom(
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withValues(alpha: 0.1),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _startEditing(index, log),
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
            ),
          ),
        ),
      ],
    );
  }

  void _showHistoryDialog(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final history = await logProvider.getHistory();

    if (history.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无历史记录')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('历史记录'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              final id = item['id'] as int;
              final name = item['name'] as String;
              final count = item['log_count'] as int;
              final createdAt = DateTime.parse(item['created_at'] as String);
              final formattedDate = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

              return ListTile(
                title: Text(name),
                subtitle: Text('$formattedDate · $count 条记录'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: '恢复',
                      onPressed: () async {
                        await logProvider.restoreFromHistory(id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已恢复历史记录')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () async {
                        await logProvider.deleteHistoryRecord(id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showHistoryDialog(context);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
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
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}