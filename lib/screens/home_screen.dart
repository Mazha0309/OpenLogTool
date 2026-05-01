import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/sync_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSession());
  }

  Future<void> _initSession() async {
    final session = context.read<SessionProvider>();
    final logProvider = context.read<LogProvider>();
    // Retry until session is ready
    for (int i = 0; i < 50; i++) {
      if (session.currentSessionId != null) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    logProvider.reloadForSession(session.currentSessionId);
  }

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

  void _showShareDialog(BuildContext context) async {
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    final sessionId = sessionProvider.currentSessionId;
    if (sessionId == null) return;

    int selectedHours = 24;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Live Share'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择过期时间：'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [1, 3, 6, 12, 24, 0].map((h) => ChoiceChip(
                  label: Text(h == 0 ? '永不过期' : '${h}小时'),
                  selected: selectedHours == h,
                  onSelected: (_) => setState(() => selectedHours = h),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(ctx),
            ),
            FilledButton(
              child: const Text('生成链接'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _generateAndShowLink(context, syncProvider, sessionId, selectedHours);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndShowLink(BuildContext context, SyncProvider syncProvider, String sessionId, int expiresIn) async {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Live Share'),
        content: Text('正在生成分享链接...'),
        actions: [],
      ),
    );

    final result = await syncProvider.createLiveShareLink(sessionId, expiresIn: expiresIn);

    if (context.mounted) {
      Navigator.pop(context);
      if (result != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('分享链接'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.url, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text('分享码: ${result.shareCode}'),
                if (result.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Text('过期时间: ${result.expiresAt}', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
            actions: [
              TextButton(
                child: const Text('复制'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.url));
                  context.showLoggedSnackBar(const SnackBar(content: Text('链接已复制')));
                  Navigator.pop(ctx);
                },
              ),
              FilledButton(
                child: const Text('关闭'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      } else {
        context.showLoggedSnackBar(const SnackBar(content: Text('获取分享链接失败')));
      }
    }
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
          children: [
            AddRecordPage(onSharePressed: () => _showShareDialog(context)),
            const ImportExportPage(),
            const SettingsPage(),
          ],
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
  final VoidCallback? onSharePressed;

  const AddRecordPage({super.key, this.onSharePressed});

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '添加点名记录',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (onSharePressed != null)
                            IconButton(
                              icon: const Icon(Icons.share),
                              tooltip: 'Live Share',
                              onPressed: onSharePressed,
                            ),
                            ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '添加点名记录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (onSharePressed != null)
                        IconButton(
                          icon: const Icon(Icons.share),
                          tooltip: 'Live Share',
                          onPressed: onSharePressed,
                        ),
                    ],
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
              final status = item['status'] as String;
              final createdAt = DateTime.parse(item['created_at'] as String);

              return ListTile(
                title: Text(name),
                subtitle: Text(
                  '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                  ' · ${status == "active" ? "进行中" : "已关闭"}'),
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
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _showDeleteSessionConfirmation(ctx, logProvider, sessionId, name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      tooltip: '彻底删除',
                      onPressed: () async {
                        await logProvider.hardDeleteSession(sessionId);
                        Navigator.pop(ctx);
                        if (context.mounted) _showHistoryDialog(context);
                      },
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
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _showDeleteSessionConfirmation(BuildContext context, LogProvider logProvider, String sessionId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$name" 吗？'),
        actions: [
          TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(ctx)),
          TextButton(
            child: const Text('删除', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              await logProvider.deleteSession(sessionId);
              Navigator.pop(ctx);
              Navigator.pop(context); // close history dialog
              if (context.mounted) {
                _showHistoryDialog(context);
              }
            },
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
            onPressed: () async {
              Navigator.pop(context);
              _showNewSessionNameDialog(context);
            },
          ),
        ],
      ),
    );
  }

  void _showNewSessionNameDialog(BuildContext context) {
    final controller = TextEditingController();
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新记录名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入本次记录名称（可留空）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text('开始新记录'),
            onPressed: () async {
              try {
                final name = controller.text.trim();
                await sessionProvider.startNewSession(title: name.isEmpty ? null : name);
                await logProvider.reloadForSession(sessionProvider.currentSessionId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    SnackBar(content: Text('已开始新记录：${name.isEmpty ? "自动命名" : name}')),
                  );
                }
              } catch (e, st) {
                debugPrint('[SessionDialog] ERROR: $e\n$st');
                Navigator.pop(ctx);
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    SnackBar(content: Text('创建新记录失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
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
