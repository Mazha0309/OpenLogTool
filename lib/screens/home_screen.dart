import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:openlogtool/widgets/log_table.dart';
import 'package:openlogtool/widgets/dictionary_manager.dart';
import 'package:openlogtool/widgets/export_panel.dart';
import 'package:openlogtool/widgets/settings_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    AddRecordPage(),
    ImportExportPage(),
    SettingsPage(),
  ];

  static const List<BottomNavigationBarItem> _navItems =
      <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.add_circle_outline, size: 24),
      activeIcon: Icon(Icons.add_circle, size: 24),
      label: '添加记录',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.import_export, size: 24),
      activeIcon: Icon(Icons.import_export, size: 24),
      label: '导入导出',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings, size: 24),
      activeIcon: Icon(Icons.settings, size: 24),
      label: '设置',
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenLogTool'),
        centerTitle: true,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: _navItems,
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}

class AddRecordPage extends StatelessWidget {
  const AddRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen =
            constraints.maxWidth > 1200 && settingsProvider.wideLayoutEnabled;

        if (isWideScreen) {
          return _buildWideLayout(context, logProvider);
        } else {
          return _buildNarrowLayout(context, logProvider);
        }
      },
    );
  }

  Widget _buildWideLayout(BuildContext context, LogProvider logProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 2,
            child: FCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '添加点名记录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const LogForm(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 2,
            child: FCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogHeader(context, logProvider),
                    const SizedBox(height: 16),
                    const Text(
                      '已有记录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const LogTable(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context, LogProvider logProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '添加点名记录',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LogForm(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogHeader(context, logProvider),
                  const SizedBox(height: 16),
                  const Text(
                    '已有记录',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LogTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogHeader(BuildContext context, LogProvider logProvider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Chip(label: Text('${logProvider.logCount} 条记录')),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FButton(
              onPress: logProvider.canUndo
                  ? () => _showUndoConfirmation(context)
                  : null,
              label: '撤销',
            ),
            const SizedBox(width: 8),
            FButton(
              style: FButtonStyle.destructive,
              onPress: logProvider.logCount > 0
                  ? () => _showClearConfirmation(context)
                  : null,
              label: '清空',
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '历史记录',
              onPressed: () => _showHistoryDialog(context),
            ),
          ],
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
                      onPressed: () => _showDeleteHistoryConfirmation(context, logProvider, id),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          FButton(
            label: '关闭',
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: '确认清空记录',
        body: '您确定要清空所有点名记录吗？此操作不可撤销！',
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            label: '确认清空',
            style: FButtonStyle.destructive,
            onPress: () {
              Provider.of<LogProvider>(context, listen: false).clearAllLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清空所有记录')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showUndoConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: '确认撤销',
        body: '您确定要撤销上一条记录吗？',
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            label: '确认撤销',
            onPress: () {
              Provider.of<LogProvider>(context, listen: false).undoLastLog();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteHistoryConfirmation(BuildContext context, LogProvider logProvider, int id) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: '确认删除',
        body: '确定要删除这条历史记录吗？',
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            label: '确认删除',
            style: FButtonStyle.destructive,
            onPress: () async {
              await logProvider.deleteHistoryRecord(id);
              Navigator.pop(context);
              if (context.mounted) {
                Navigator.pop(context);
                _showHistoryDialog(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class ImportExportPage extends StatelessWidget {
  const ImportExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen =
            constraints.maxWidth > 900 && settingsProvider.wideLayoutEnabled;

        if (isWideScreen) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ExportPanel(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: DictionaryManager(),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ExportPanel(),
                  ),
                ),
                const SizedBox(height: 16),
                FCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: DictionaryManager(),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SettingsPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
