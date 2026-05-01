import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';

class LogTable extends StatefulWidget {
  const LogTable({super.key});

  @override
  State<LogTable> createState() => _LogTableState();
}

class _LogTableState extends State<LogTable> {
  int? _editingIndex;
  late Map<String, TextEditingController> _controllers;
  int _currentPage = 0;
  static const int _itemsPerPage = 5;

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
    final settingsProvider = Provider.of<SettingsProvider>(context);

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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 如果高度无限，使用一个默认高度
        final maxHeight = constraints.maxHeight.isFinite 
            ? constraints.maxHeight 
            : 400.0;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: maxHeight,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) => true,
                child: Scrollbar(
                  controller: horizontalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: horizontalController,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                          columns: [
                            DataColumn(
                              label: _buildCenteredCell(const Text('#'), 60),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('时间'), 100),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('点名主控'), 120),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('呼号'), 120),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('信号报告'), 100),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('QTH'), 150),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('设备'), 150),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('功率'), 80),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('天线'), 150),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('高度'), 80),
                            ),
                            DataColumn(
                              label: _buildCenteredCell(const Text('操作'), 120),
                            ),
                          ],
                          rows: _buildTableRows(context, logProvider, settingsProvider),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 分页控件
            if (settingsProvider.paginationEnabled && logProvider.logs.length > _itemsPerPage)
              _buildPaginationControls(logProvider.logs.length),
          ],
        );
      },
    );
  }

  List<DataRow> _buildTableRows(BuildContext context, LogProvider logProvider, SettingsProvider settingsProvider) {
    final logs = logProvider.logs;
    final indexedLogs = logs.asMap().entries.toList().reversed.toList();

    // 如果启用分页，只显示当前页的数据（按最新在上排序后的结果）
    List<MapEntry<int, LogEntry>> displayEntries;
    if (settingsProvider.paginationEnabled) {
      final startIndex = _currentPage * _itemsPerPage;
      final endIndex = (startIndex + _itemsPerPage).clamp(0, indexedLogs.length);
      displayEntries = indexedLogs.sublist(startIndex, endIndex);
    } else {
      displayEntries = indexedLogs;
    }

    return displayEntries.asMap().entries.map((entry) {
      final originalIndex = entry.value.key;
      final log = entry.value.value;
      final isEditing = _editingIndex == originalIndex;
      // 倒序序号：最新的记录显示最大序号
      final reverseIndex = originalIndex + 1;

      return DataRow(
        cells: [
          DataCell(
            _buildCenteredCell(Text('$reverseIndex'), 60),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _controllers['time'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.time), 100),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _controllers['controller'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.controller), 120),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _controllers['callsign'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.callsign), 120),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _controllers['report'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.report), 100),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['qth'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.qth), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['device'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.device), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _controllers['power'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.power), 80),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['antenna'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.antenna), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _controllers['height'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.height), 80),
          ),
          DataCell(
            _buildCenteredCell(
              isEditing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          onPressed: () => _saveEditing(originalIndex),
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
                          onPressed: () => _startEditing(originalIndex, log),
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
                          onPressed: () => _showDeleteConfirmation(context, originalIndex),
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
              120,
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildCenteredCell(Widget child, double width) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems) {
    final totalPages = (totalItems / _itemsPerPage).ceil();
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          const SizedBox(width: 8),
          Text('${_currentPage + 1} / $totalPages'),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final sessions = await logProvider.getHistory();

    if (sessions.isEmpty) {
      if (context.mounted) {
        context.showLoggedSnackBar(const SnackBar(content: Text('暂无历史记录')));
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('历史记录'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (_, index) {
              final item = sessions[index];
              final sessionId = item['session_id'] as String;
              final name = item['title'] as String;
              final createdAt = DateTime.parse(item['created_at'] as String);

              return ListTile(
                title: Text(name),
                subtitle: Text(
                  '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: '打开',
                      onPressed: () async {
                        await logProvider.switchToSession(sessionId);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          context.showLoggedSnackBar(
                            SnackBar(content: Text('已切换到: $name')),
                          );
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
          FilledButton(child: const Text('关闭'), onPressed: () => Navigator.pop(ctx)),
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
              context.showLoggedSnackBar(
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
