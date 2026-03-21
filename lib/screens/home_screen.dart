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

/// 主屏幕组件
/// 包含底部导航栏，用于在"添加记录"、"导入导出"、"设置"三个页面之间切换
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
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              floating: true,
              pinned: true,
              title: const Text('OpenLogTool'),
              centerTitle: true,
              forceElevated: innerBoxIsScrolled,
            ),
          ];
        },
        body: _pages[_selectedIndex],
      ),
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

/// 添加记录页面
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
          // 宽屏布局：左右分栏
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：表单
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

                // 右侧：表格
                Flexible(
                  flex: 2,
                  child: FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
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
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '已有记录',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Expanded(child: LogTable()),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // 窄屏布局：垂直堆叠
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
                const SizedBox(height: 24),
                FCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
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
                              ],
                            ),
                          ],
                        ),
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
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      },
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
            onPress: () => Navigator.pop(context),
            label: '取消',
          ),
          FButton(
            onPress: () {
              Provider.of<LogProvider>(context, listen: false).undoLastLog();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已撤销上一条记录'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            label: '确认撤销',
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
            onPress: () => Navigator.pop(context),
            label: '取消',
          ),
          FButton(
            style: FButtonStyle.destructive,
            onPress: () {
              Provider.of<LogProvider>(context, listen: false).clearAllLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已清空所有记录'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            label: '确认清空',
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
          // 宽屏布局：左右分栏
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
          // 窄屏布局：垂直堆叠
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
