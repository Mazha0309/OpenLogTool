import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/rust_log_provider.dart';
import 'package:openlogtool/providers/rust_session_provider.dart';
import 'package:openlogtool/providers/rust_dict_provider.dart';
import 'package:openlogtool/providers/rust_settings_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart';

class RustHomeScreen extends StatefulWidget {
  const RustHomeScreen({super.key});

  @override
  State<RustHomeScreen> createState() => _RustHomeScreenState();
}

class _RustHomeScreenState extends State<RustHomeScreen> {
  int _tab = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final rsp = context.read<RustSessionProvider>();
    final rlp = context.read<RustLogProvider>();
    final rdp = context.read<RustDictProvider>();

    await rdp.seedFromAssets();
    await rsp.loadSessions();

    if (rsp.sessions.isEmpty) {
      await rsp.createSession('晚点名');
    } else {
      rsp.selectSession(rsp.sessions.first);
    }

    final session = rsp.currentSession;
    if (session != null) {
      await rlp.loadLogs(session.sessionId);
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('OpenLogTool')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('OpenLogTool')),
      body: IndexedStack(
        index: _tab,
        children: [
          _LogPage(),
          _DictPage(),
          _SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '记录'),
          BottomNavigationBarItem(icon: Icon(Icons.dns), label: '词典'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

// ─── Log Page ─────────────────────────────────────────────────

class _LogPage extends StatefulWidget {
  @override
  State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  final _callsignCtrl = TextEditingController();
  final _controllerCtrl = TextEditingController(text: 'BG7XXX');
  final _rstSentCtrl = TextEditingController();
  final _rstRcvdCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _antennaCtrl = TextEditingController();
  final _qthCtrl = TextEditingController();
  final _powerCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _controllerCtrl.dispose();
    _rstSentCtrl.dispose();
    _rstRcvdCtrl.dispose();
    _deviceCtrl.dispose();
    _antennaCtrl.dispose();
    _qthCtrl.dispose();
    _powerCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rsp = context.read<RustSessionProvider>();
    final rlp = context.read<RustLogProvider>();
    final rdp = context.read<RustDictProvider>();
    final session = rsp.currentSession;
    if (session == null || _callsignCtrl.text.trim().isEmpty) return;

    await rlp.addLog(
      sessionId: session.sessionId,
      controller: _controllerCtrl.text.trim(),
      callsign: _callsignCtrl.text.trim(),
      rstSent: _rstSentCtrl.text.trim(),
      rstRcvd: _rstRcvdCtrl.text.trim(),
      device: _deviceCtrl.text.trim(),
      antenna: _antennaCtrl.text.trim(),
      qth: _qthCtrl.text.trim(),
      power: _powerCtrl.text.trim(),
      height: _heightCtrl.text.trim(),
    );

    for (final entry in [
      ('callsign', _callsignCtrl.text.trim()),
      ('device', _deviceCtrl.text.trim()),
      ('antenna', _antennaCtrl.text.trim()),
      ('qth', _qthCtrl.text.trim()),
    ]) {
      if (entry.$2.isNotEmpty) await rdp.addDictItem(entry.$1, entry.$2);
    }

    _callsignCtrl.clear();
    _rstSentCtrl.clear();
    _rstRcvdCtrl.clear();
    _deviceCtrl.clear();
    _antennaCtrl.clear();
    _qthCtrl.clear();
    _powerCtrl.clear();
    _heightCtrl.clear();
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget build(BuildContext context) {
    final rlp = context.watch<RustLogProvider>();
    final rsp = context.watch<RustSessionProvider>();
    final session = rsp.currentSession;
    final theme = Theme.of(context);

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerTheme.color!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(session?.title ?? '未选择会话', style: theme.textTheme.titleLarge),
              ),
              if (rlp.stats != null) ...[
                _chip(context, '总计', '${rlp.stats!.total}'),
                const SizedBox(width: 8),
                _chip(context, '今日', '${rlp.stats!.today}'),
                const SizedBox(width: 8),
                _chip(context, '7日', '${rlp.stats!.last7Days}'),
              ],
            ],
          ),
        ),
        // Form
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(flex: 3, child: _field('主控呼号', _controllerCtrl)),
                    const SizedBox(width: 8),
                    Expanded(flex: 4, child: _field('点名呼号', _callsignCtrl)),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _field('RST发', _rstSentCtrl)),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _field('RST收', _rstRcvdCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _field('设备', _deviceCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('天线', _antennaCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('QTH', _qthCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('功率', _powerCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('高度', _heightCtrl)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加记录'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: rlp.logs.isNotEmpty
                          ? () async {
                              if (session != null) await rlp.undoLastLog(session.sessionId);
                            }
                          : null,
                      child: const Text('撤销'),
                    ),
                    const Spacer(),
                    if (session != null) ...[
                      OutlinedButton.icon(
                        onPressed: () => RustApi.exportJson(sessionId: session.sessionId),
                        icon: const Icon(Icons.code, size: 16),
                        label: const Text('JSON'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => RustApi.exportExcel(sessionId: session.sessionId),
                        icon: const Icon(Icons.table_chart, size: 16),
                        label: const Text('Excel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        // Table
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: rlp.logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt, size: 48, color: theme.colorScheme.onSurface.withAlpha(60)),
                        const SizedBox(height: 12),
                        Text('暂无记录', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withAlpha(100))),
                        const SizedBox(height: 4),
                        Text('在上方表单中添加第一条记录', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Table header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: theme.dividerTheme.color!)),
                          color: theme.colorScheme.surface.withAlpha(180),
                        ),
                        child: Row(
                          children: [
                            _hCell('时间', 1.2),
                            _hCell('主控', 1.5),
                            _hCell('呼号', 1.8),
                            _hCell('RST', 1.5),
                            _hCell('设备', 2),
                            _hCell('QTH', 1.5),
                          ],
                        ),
                      ),
                      // Table rows
                      ...rlp.logs.asMap().entries.map((entry) {
                        final log = entry.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: theme.dividerTheme.color!.withAlpha(80))),
                          ),
                          child: Row(
                            children: [
                              _cell(log.time.length >= 16 ? log.time.substring(11, 16) : log.time, 1.2, theme),
                              _cell(log.controller, 1.5, theme),
                              _cell(log.callsign, 1.8, theme, bold: true),
                              _cell('${log.rstSent ?? ""}/${log.rstRcvd ?? ""}', 1.5, theme),
                              _cell(log.device ?? '', 2, theme),
                              _cell(log.qth ?? '', 1.5, theme),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _hCell(String label, double flex) {
    final theme = Theme.of(context);
    return Expanded(
      flex: (flex * 10).round(),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }

  Widget _cell(String text, double flex, ThemeData theme, {bool bold = false}) {
    return Expanded(
      flex: (flex * 10).round(),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: theme.colorScheme.onSurface,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}

Widget _chip(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: theme.colorScheme.secondary.withAlpha(120),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
      ],
    ),
  );
}

// ─── Dict Page ────────────────────────────────────────────────

class _DictPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rdp = context.watch<RustDictProvider>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _dictSection(context, '设备', rdp.deviceDict),
        const SizedBox(height: 8),
        _dictSection(context, '天线', rdp.antennaDict),
        const SizedBox(height: 8),
        _dictSection(context, '呼号', rdp.callsignDict),
        const SizedBox(height: 8),
        _dictSection(context, 'QTH', rdp.qthDict),
      ],
    );
  }

  Widget _dictSection(BuildContext context, String title, List items) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.take(30).map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(item.raw, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Page ────────────────────────────────────────────

class _SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rsp = context.watch<RustSettingsProvider>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题设置', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('暗色模式'),
                  subtitle: const Text('切换深色/浅色主题'),
                  value: rsp.isDarkMode,
                  onChanged: (v) => rsp.setDarkMode(v),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                ListTile(
                  title: const Text('版本'),
                  subtitle: const Text('1.0.0'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
