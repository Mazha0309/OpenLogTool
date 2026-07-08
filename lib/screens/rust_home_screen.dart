import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/src/widgets/shadcn/mod.dart';
import 'package:openlogtool/providers/rust_log_provider.dart';
import 'package:openlogtool/providers/rust_session_provider.dart';
import 'package:openlogtool/providers/rust_dict_provider.dart';
import 'package:openlogtool/providers/rust_settings_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart';

class RustHomeScreen extends StatefulWidget {
  const RustHomeScreen({super.key});

  @override
  State<RustHomeScreen> createState() => _RustHomeScreenState();
}

class _RustHomeScreenState extends State<RustHomeScreen> {
  final _callsignCtrl = TextEditingController();
  final _rstSentCtrl = TextEditingController();
  final _rstRcvdCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _antennaCtrl = TextEditingController();
  final _qthCtrl = TextEditingController();
  final _powerCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _controllerCtrl = TextEditingController(text: 'BG7XXX');
  bool _ready = false;
  int _tab = 0;

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
      await rsp.createSession('2026-07-08 晚点名');
    } else {
      rsp.selectSession(rsp.sessions.first);
    }

    final session = rsp.currentSession;
    if (session != null) {
      await rlp.loadLogs(session.sessionId);
    }

    setState(() => _ready = true);
  }

  Future<void> _submit() async {
    final rsp = context.read<RustSessionProvider>();
    final rlp = context.read<RustLogProvider>();
    final rdp = context.read<RustDictProvider>();
    final session = rsp.currentSession;
    if (session == null) return;

    final callsign = _callsignCtrl.text.trim();
    if (callsign.isEmpty) return;

    await rlp.addLog(
      sessionId: session.sessionId,
      controller: _controllerCtrl.text.trim(),
      callsign: callsign,
      rstSent: _rstSentCtrl.text.trim(),
      rstRcvd: _rstRcvdCtrl.text.trim(),
      device: _deviceCtrl.text.trim(),
      antenna: _antennaCtrl.text.trim(),
      qth: _qthCtrl.text.trim(),
      power: _powerCtrl.text.trim(),
      height: _heightCtrl.text.trim(),
    );

    await rdp.addDictItem('callsign', callsign);
    if (_deviceCtrl.text.trim().isNotEmpty) {
      await rdp.addDictItem('device', _deviceCtrl.text.trim());
    }
    if (_antennaCtrl.text.trim().isNotEmpty) {
      await rdp.addDictItem('antenna', _antennaCtrl.text.trim());
    }
    if (_qthCtrl.text.trim().isNotEmpty) {
      await rdp.addDictItem('qth', _qthCtrl.text.trim());
    }

    _callsignCtrl.clear();
    _rstSentCtrl.clear();
    _rstRcvdCtrl.clear();
    _deviceCtrl.clear();
    _antennaCtrl.clear();
    _qthCtrl.clear();
    _powerCtrl.clear();
    _heightCtrl.clear();
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _rstSentCtrl.dispose();
    _rstRcvdCtrl.dispose();
    _deviceCtrl.dispose();
    _antennaCtrl.dispose();
    _qthCtrl.dispose();
    _powerCtrl.dispose();
    _heightCtrl.dispose();
    _controllerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenLogTool'),
        centerTitle: false,
        actions: [
          Consumer<RustSettingsProvider>(
            builder: (_, sp, __) => ShIconButton(
              icon: sp.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              onPressed: () => sp.setDarkMode(!sp.isDarkMode),
            ),
          ),
        ],
      ),
      body: _ready ? _buildBody() : const Center(child: CircularProgressIndicator()),
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

  Widget _buildBody() {
    switch (_tab) {
      case 0: return _buildLogPage();
      case 1: return _buildDictPage();
      case 2: return _buildSettingsPage();
      default: return const SizedBox();
    }
  }

  Widget _buildLogPage() {
    final rsp = context.watch<RustSessionProvider>();
    final rlp = context.watch<RustLogProvider>();
    final session = rsp.currentSession;

    return Column(
      children: [
        // Session bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color!)),
          ),
          child: Row(
            children: [
              Text(session?.title ?? '未选择会话', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (rlp.stats != null) ...[
                _StatChip(label: '总计', value: '${rlp.stats!.total}'),
                const SizedBox(width: 8),
                _StatChip(label: '今日', value: '${rlp.stats!.today}'),
              ],
            ],
          ),
        ),
        // Form
        ShCard(
          margin: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: ShInput(label: '主控', controller: _controllerCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: '呼号', controller: _callsignCtrl, autofocus: true)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: 'RST 发', controller: _rstSentCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: 'RST 收', controller: _rstRcvdCtrl)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: ShInput(label: '设备', controller: _deviceCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: '天线', controller: _antennaCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: 'QTH', controller: _qthCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: '功率', controller: _powerCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: ShInput(label: '高度', controller: _heightCtrl)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ShButton(label: '录入', icon: Icons.add, onPressed: _submit),
                  const SizedBox(width: 8),
                  ShButton(
                    label: '撤销',
                    variant: ShButtonVariant.outline,
                    onPressed: rlp.logs.isNotEmpty
                        ? () async {
                            if (session != null) {
                              await rlp.undoLastLog(session.sessionId);
                            }
                          }
                        : null,
                  ),
                  const Spacer(),
                  if (session != null) ...[
                    ShButton(
                      label: 'JSON',
                      variant: ShButtonVariant.secondary,
                      onPressed: () async {
                        await RustApi.exportJson(sessionId: session.sessionId);
                      },
                    ),
                    const SizedBox(width: 8),
                    ShButton(
                      label: 'Excel',
                      variant: ShButtonVariant.secondary,
                      onPressed: () async {
                        await RustApi.exportExcel(sessionId: session.sessionId);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Table
        Expanded(
          child: ShCard(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: EdgeInsets.zero,
            child: ShTable(
              columns: [
                ShColumn(label: '时间', flex: 1.5, cellBuilder: (r) => (r as LogEntry).time.substring(11, 16)),
                ShColumn(label: '呼号', flex: 2, cellBuilder: (r) => (r as LogEntry).callsign),
                ShColumn(label: '发/收', flex: 2, cellBuilder: (r) {
                  final e = r as LogEntry;
                  return '${e.rstSent ?? ""}/${e.rstRcvd ?? ""}';
                }),
                ShColumn(label: '设备', flex: 2.5, cellBuilder: (r) => (r as LogEntry).device ?? ''),
                ShColumn(label: 'QTH', flex: 2, cellBuilder: (r) => (r as LogEntry).qth ?? ''),
              ],
              rows: rlp.logs,
              emptyMessage: '暂无记录，请添加',
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDictPage() {
    final rdp = context.watch<RustDictProvider>();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _DictSection(title: '设备', items: rdp.deviceDict),
        const SizedBox(height: 8),
        _DictSection(title: '天线', items: rdp.antennaDict),
        const SizedBox(height: 8),
        _DictSection(title: '呼号', items: rdp.callsignDict),
        const SizedBox(height: 8),
        _DictSection(title: 'QTH', items: rdp.qthDict),
      ],
    );
  }

  Widget _buildSettingsPage() {
    final rsp = context.watch<RustSettingsProvider>();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ShCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShCardHeader(title: '主题'),
              SwitchListTile(
                title: const Text('暗色模式'),
                value: rsp.isDarkMode,
                onChanged: (v) => rsp.setDarkMode(v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withAlpha(80),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(width: 4),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DictSection extends StatelessWidget {
  final String title;
  final List<DictItem> items;

  const _DictSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ShCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items.take(20).map((item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withAlpha(60),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(item.raw, style: theme.textTheme.bodySmall),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
