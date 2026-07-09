import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
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
    final sp = context.read<SessionProvider>();
    final lp = context.read<LogProvider>();
    await sp.ready;
    if (!mounted) return;
    if (sp.currentSessionId == null) {
      final ctrl = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新记录名称'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入本次记录名称（可留空）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            FilledButton(
              child: const Text('开始新记录'),
              onPressed: () async {
                final name = ctrl.text.trim();
                await sp.startNewSession(title: name.isEmpty ? null : name);
                await lp.reloadForSession(sp.currentSessionId);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
      return;
    }
    lp.reloadForSession(sp.currentSessionId);
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

  void _showShareOptions(BuildContext context) {
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
    final sessionId = sessionProvider.currentSessionId;
    if (sessionId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('分享'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('上传到服务器'),
              subtitle: const Text('上传当前会话，其他人可通过 Liveshare 查看'),
              onTap: () {
                Navigator.pop(ctx);
                _shareSession(context, sessionId);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('从服务器下载'),
              subtitle: const Text('查看服务器上的其他会话'),
              onTap: () {
                Navigator.pop(ctx);
                _showJoinShareDialog(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }


  Future<void> _shareSession(BuildContext context, String sessionId) async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    final lp = Provider.of<LogProvider>(context, listen: false);
    final sv = Provider.of<ServerProvider>(context, listen: false);
    if (!sv.isLoggedIn) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中登录服务器')),
      );
      return;
    }
    try {
      await sv.uploadSession(sessionId, sp.currentSession?.title ?? '', lp.logs.map((l) => l.toMap()).toList());
      if (context.mounted) {
        final url = '${sv.serverUrl}/live/$sessionId';
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('已分享'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('其他人可通过以下链接实时查看：'),
                const SizedBox(height: 8),
                SelectableText(url, style: const TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败: $e')),
      );
    }
  }

  void _showJoinShareDialog(BuildContext context) async {
    final sv = Provider.of<ServerProvider>(context, listen: false);
    if (!sv.isLoggedIn) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中登录服务器')),
      );
      return;
    }
    try {
      final sessions = await sv.listSessions();
      if (!context.mounted) return;
      if (sessions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器上没有会话')),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('服务器上的会话'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                return ListTile(
                  title: Text(s['title']?.toString() ?? ''),
                  subtitle: Text(s['created_at']?.toString() ?? ''),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final data = await sv.downloadSession(s['id']);
                      final sp = Provider.of<SessionProvider>(context, listen: false);
                      final lp = Provider.of<LogProvider>(context, listen: false);
                      await sp.startNewSession(title: data['title'] ?? '');
                      if (data['logs'] is List) {
                        for (final logData in data['logs']) {
                          await lp.addLog(LogEntry.fromJson(logData as Map<String, dynamic>), sessionId: sp.currentSessionId);
                        }
                      }
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已下载并切换到该会话')),
                      );
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('下载失败: $e')),
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取会话列表失败: $e')),
      );
    }
  }

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
            AddRecordPage(onSharePressed: () => _showShareOptions(context), onJoinPressed: () => _showJoinShareDialog(context)),
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
  final VoidCallback? onJoinPressed;

  const AddRecordPage({super.key, this.onSharePressed, this.onJoinPressed});

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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (onSharePressed != null)
                                IconButton(
                                  icon: const Icon(Icons.share, size: 20),
                                  tooltip: '分享',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: onSharePressed,
                                ),
                              if (onJoinPressed != null)
                                IconButton(
                                  icon: const Icon(Icons.group_add, size: 20),
                                  tooltip: '加入合作',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: onJoinPressed,
                                ),
                            ],
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onSharePressed != null)
                            IconButton(
                              icon: const Icon(Icons.share, size: 20),
                              tooltip: '分享',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: onSharePressed,
                            ),
                          if (onJoinPressed != null)
                            IconButton(
                              icon: const Icon(Icons.group_add, size: 20),
                              tooltip: '加入合作',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: onJoinPressed,
                            ),
                        ],
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
        Flexible(
          child: Consumer<LogProvider>(
            builder: (_, lp, __) => Chip(label: Text('${lp.logCount} 条记录')),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<LogProvider>(
              builder: (_, lp, __) => FilledButton(
                onPressed: lp.canUndo
                    ? () => _showUndoConfirmation(context)
                    : null,
                child: const Text('撤销'),
              ),
            ),
            const SizedBox(width: 8),
            Consumer<LogProvider>(
              builder: (_, lp, __) => FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
                onPressed: lp.logCount > 0
                    ? () => _showClearConfirmation(context)
                    : null,
                child: const Text('清空'),
              ),
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
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
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
              final isCurrent = sessionProvider.currentSessionId == sessionId;

              return ListTile(
                title: Text(name),
                subtitle: Text(
                  '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                  ' · ${status == "active" ? "进行中" : "已关闭"}${isCurrent ? ' · 当前' : ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: '打开',
                      onPressed: isCurrent
                          ? null
                          : () async {
                              await sessionProvider.switchToSession(sessionId);
                              await logProvider.reloadForSession(sessionId);
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
                      tooltip: '关闭',
                      onPressed: isCurrent
                          ? null
                          : () => _showDeleteSessionConfirmation(ctx, logProvider, sessionProvider, sessionId, name),
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

  void _showDeleteSessionConfirmation(BuildContext context, LogProvider logProvider, SessionProvider sessionProvider, String sessionId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认关闭'),
        content: Text('确定要关闭 "$name" 吗？关闭后可在历史记录中查看，但无法再添加记录。'),
        actions: [
          TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(ctx)),
          TextButton(
            child: const Text('关闭', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              await logProvider.hardDeleteSession(sessionId);
              if (sessionProvider.currentSessionId == sessionId) {
                await sessionProvider.handleSessionDeleted(sessionId);
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (context.mounted) {
                Navigator.pop(context); // close history dialog
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              _showNewSessionNameDialog(context);
            },
            child: const Text('确认清空'),
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
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
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
          return const SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ExportPanel(),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: DictionaryManager(),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return const SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: ExportPanel(),
                  ),
                ),
                SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
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
          child: const SettingsPanel(),
        );
      },
    );
  }
}
