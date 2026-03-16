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

  // 页面列表
  static const List<Widget> _pages = <Widget>[
    AddRecordPage(),
    ImportExportPage(),
    SettingsPage(),
  ];

  // 底部导航栏项目
  static const List<BottomNavigationBarItem> _navItems = <BottomNavigationBarItem>[
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
        title: const Text('业余无线电点名记录工具'),
        centerTitle: true,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: _navItems,
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}

// 添加记录页面（支持宽屏布局）
class AddRecordPage extends StatelessWidget {
  const AddRecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 800 && settingsProvider.wideLayoutEnabled;
        
        if (isWideScreen) {
          // 宽屏布局：左侧添加表单，右侧表格
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：添加记录表单
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // 工具栏
                        _buildToolbar(context, logProvider),
                        const SizedBox(height: 16),
                        
                        // 添加记录表单卡片
                        FCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                        
                        // 统计卡片
                        _buildStatsCard(context, logProvider),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 右侧：记录表格
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        FCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                  ),
                ),
              ),
            ],
          );
        } else {
          // 窄屏布局：垂直堆叠
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 工具栏
                  _buildToolbar(context, logProvider),
                  const SizedBox(height: 16),
                  
                  // 添加记录表单卡片
                  FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                  
                  // 记录表格卡片
                  FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                  
                  // 统计卡片
                  _buildStatsCard(context, logProvider),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildToolbar(BuildContext context, LogProvider logProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '点名记录管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              Chip(
                label: Text('${logProvider.logCount} 条记录'),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.1),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('撤销'),
                onPressed: logProvider.canUndo
                    ? () => _showUndoConfirmation(context)
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('清空所有'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: logProvider.logCount > 0
                    ? () => _showClearConfirmation(context)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, LogProvider logProvider) {
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '统计信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context,
                  '总记录数',
                  '${logProvider.logCount}',
                  Icons.format_list_numbered,
                ),
                _buildStatItem(
                  context,
                  '今日记录',
                  '${logProvider.todayLogCount}',
                  Icons.today,
                ),
                _buildStatItem(
                  context,
                  '最近7天',
                  '${logProvider.last7DaysCount}',
                  Icons.calendar_view_week,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  void _showUndoConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认撤销'),
        content: const Text('您确定要撤销上一条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).undoLastLog();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已撤销上一条记录'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('确认撤销'),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<LogProvider>(context, listen: false).clearAllLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已清空所有记录'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}

// 导入导出页面
class ImportExportPage extends StatelessWidget {
  const ImportExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
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
      ),
    );
  }
}

// 设置页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SettingsPanel(),
          ),
        ),
      ),
    );
  }
}
