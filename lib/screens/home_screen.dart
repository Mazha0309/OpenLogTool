import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:openlogtool/widgets/log_table.dart';
import 'package:openlogtool/widgets/dictionary_manager.dart';
import 'package:openlogtool/widgets/export_panel.dart';
import 'package:openlogtool/widgets/settings_panel.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isBottomNavVisible = true;
  double _lastScrollOffset = 0;

  void _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final currentOffset = notification.metrics.pixels;
      if (currentOffset > _lastScrollOffset && currentOffset > 50) {
        if (_isBottomNavVisible) {
          setState(() => _isBottomNavVisible = false);
        }
      } else if (currentOffset < _lastScrollOffset - 10) {
        if (!_isBottomNavVisible) {
          setState(() => _isBottomNavVisible = true);
        }
      }
      _lastScrollOffset = currentOffset;
    }
  }

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
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onScroll(notification);
          return false;
        },
        child: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _isBottomNavVisible ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: value,
              child: child,
            ),
          );
        },
        child: BottomNavigationBar(
          items: _navItems,
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
        ),
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
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(
                      width: double.infinity,
                      child: LogForm(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Card(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '添加点名记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const LogForm(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogHeader(context, logProvider),
                  const SizedBox(height: 12),
                  const Text(
                    '已有记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
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
            FilledButton(
              onPressed: logProvider.canUndo
                  ? () => _showUndoConfirmation(context)
                  : null,
              child: const Text('撤销'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
              onPressed: logProvider.logCount > 0
                  ? () => _showClearConfirmation(context)
                  : null,
              child: const Text('清空'),
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
        context.showLoggedSnackBar(
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
              final formattedDate =
                  '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

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
                          context.showLoggedSnackBar(
                            const SnackBar(content: Text('已恢复历史记录')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _showDeleteHistoryConfirmation(
                          context, logProvider, id),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空记录'),
        content: const Text('您确定要清空所有点名记录吗？此操作不可撤销！'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('确认清空'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).clearAllLogs();
              Navigator.pop(context);
              context.showLoggedSnackBar(
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
      builder: (context) => AlertDialog(
        title: const Text('确认撤销'),
        content: const Text('您确定要撤销上一条记录吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('确认撤销'),
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).undoLastLog();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteHistoryConfirmation(
      BuildContext context, LogProvider logProvider, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条历史记录吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('确认删除'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () async {
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
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ExportPanel(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Card(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: ExportPanel(),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 16, vertical: isNarrow ? 12 : 16),
          child: SettingsPanel(),
        );
      },
    );
  }
}
