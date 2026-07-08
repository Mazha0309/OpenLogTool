import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/rust_log_provider.dart';
import 'package:openlogtool/providers/rust_session_provider.dart';
import 'package:openlogtool/providers/rust_dict_provider.dart';
import 'package:openlogtool/providers/rust_settings_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart';
import 'dart:async';

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
        children: const [
          _LogPage(),
          _DictPage(),
          _SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: '添加记录'),
          BottomNavigationBarItem(icon: Icon(Icons.dns_outlined), label: '词典'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}

// ─── Log Page ─────────────────────────────────────────────

class _LogPage extends StatefulWidget {
  const _LogPage();

  @override
  State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllerCtrl = TextEditingController();
  final _callsignCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _antennaCtrl = TextEditingController();
  final _powerCtrl = TextEditingController();
  final _qthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _rstSentCtrl = TextEditingController();
  final _rstRcvdCtrl = TextEditingController();

  String? _controllerError;

  @override
  void dispose() {
    _controllerCtrl.dispose();
    _callsignCtrl.dispose();
    _deviceCtrl.dispose();
    _antennaCtrl.dispose();
    _powerCtrl.dispose();
    _qthCtrl.dispose();
    _heightCtrl.dispose();
    _rstSentCtrl.dispose();
    _rstRcvdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controllerCtrl.text.trim().isEmpty) {
      setState(() => _controllerError = '请输入主控呼号');
      return;
    }
    setState(() => _controllerError = null);

    final rlp = context.read<RustLogProvider>();
    final rdp = context.read<RustDictProvider>();
    final rsp = context.read<RustSessionProvider>();
    final session = rsp.currentSession;
    if (session == null) return;

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

    // Auto-add to dictionaries
    if (_deviceCtrl.text.trim().isNotEmpty) await rdp.addDictItem('device', _deviceCtrl.text.trim());
    if (_antennaCtrl.text.trim().isNotEmpty) await rdp.addDictItem('antenna', _antennaCtrl.text.trim());
    if (_callsignCtrl.text.trim().isNotEmpty) await rdp.addDictItem('callsign', _callsignCtrl.text.trim());
    if (_qthCtrl.text.trim().isNotEmpty) await rdp.addDictItem('qth', _qthCtrl.text.trim());

    _callsignCtrl.clear();
    _deviceCtrl.clear();
    _antennaCtrl.clear();
    _powerCtrl.clear();
    _qthCtrl.clear();
    _heightCtrl.clear();
    _rstSentCtrl.clear();
    _rstRcvdCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rlp = context.watch<RustLogProvider>();
    final rsp = context.watch<RustSessionProvider>();
    final rdp = context.watch<RustDictProvider>();
    final session = rsp.currentSession;
    final logs = rlp.logs;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 420,
                child: _buildForm(context, rdp, rlp, wide, session),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildTable(context, logs, rlp, session)),
            ],
          );
        }

        return Column(
          children: [
            _buildStats(context),
            _buildForm(context, rdp, rlp, wide, session),
            Expanded(child: _buildTable(context, logs, rlp, session)),
          ],
        );
      },
    );
  }

  Widget _buildStats(BuildContext context) {
    final rlp = context.watch<RustLogProvider>();
    final rsp = context.watch<RustSessionProvider>();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(rsp.currentSession?.title ?? '未选择', style: theme.textTheme.titleMedium),
          const Spacer(),
          if (rlp.stats != null) ...[
            _chip(theme, '${rlp.stats!.total}', '总计'),
            const SizedBox(width: 8),
            _chip(theme, '${rlp.stats!.today}', '今日'),
          ],
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(150),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onPrimaryContainer.withAlpha(180))),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, RustDictProvider rdp, RustLogProvider rlp, bool wide, dynamic session) {
    final theme = Theme.of(context);
    final spacing = wide ? 12.0 : 8.0;
    final isNarrow = !wide;

    return Card(
      margin: EdgeInsets.all(wide ? 12 : 8),
      child: Padding(
        padding: EdgeInsets.all(wide ? 16 : 12),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: _fw(wide ? 420 : null, 2),
                    child: _field('主控呼号 *', _controllerCtrl, error: _controllerError),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 2),
                    child: _autoField('点名呼号', _callsignCtrl, rdp.callsignDict),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 1),
                    child: _field('RST 发', _rstSentCtrl),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 1),
                    child: _field('RST 收', _rstRcvdCtrl),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 2),
                    child: _autoField('设备', _deviceCtrl, rdp.deviceDict),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 2),
                    child: _autoField('天线', _antennaCtrl, rdp.antennaDict),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 1),
                    child: _field('功率', _powerCtrl),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 2),
                    child: _autoField('QTH', _qthCtrl, rdp.qthDict),
                  ),
                  SizedBox(
                    width: _fw(wide ? 420 : null, 1),
                    child: _field('高度', _heightCtrl),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加记录'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (session != null && rlp.logs.isNotEmpty)
                        ? () => rlp.undoLastLog(session!.sessionId)
                        : null,
                    child: const Text('撤销'),
                  ),
                  if (wide) ...[
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _fw(double? parentWidth, int cols) {
    if (parentWidth == null) {
      // narrow: auto-calculate based on cols
      return cols > 1 ? 200 : 160;
    }
    // wide: fixed card width 420, fields per row
    return (parentWidth - 12) / 2;
  }

  Widget _field(String label, TextEditingController ctrl, {String? error}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
      textCapitalization: TextCapitalization.characters,
    );
  }

  Widget _autoField(String label, TextEditingController ctrl, List<DictItem> options) {
    return Autocomplete<DictItem>(
      optionsBuilder: (text) {
        if (text.text.isEmpty) return [];
        final q = text.text.toUpperCase();
        return options.where((o) => o.raw.toUpperCase().contains(q));
      },
      onSelected: (s) => ctrl.text = s.raw,
      fieldViewBuilder: (ctx, fc, fn, onSubmit) {
        ctrl.addListener(() {
          if (fc.text != ctrl.text) fc.text = ctrl.text;
        });
        return TextFormField(
          controller: fc,
          focusNode: fn,
          decoration: InputDecoration(labelText: label, isDense: true),
          style: const TextStyle(fontSize: 14),
          textCapitalization: TextCapitalization.characters,
          onChanged: (v) {
            ctrl.text = v.toUpperCase();
          },
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 160,
              width: 280,
              child: ListView(
                padding: EdgeInsets.zero,
                children: options.map((o) => ListTile(
                  dense: true,
                  title: Text(o.raw, style: const TextStyle(fontSize: 13)),
                  onTap: () => onSelected(o),
                )).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTable(BuildContext context, List<LogEntry> logs, RustLogProvider rlp, dynamic session) {
    final theme = Theme.of(context);

    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.list_alt, size: 64, color: theme.colorScheme.onSurface.withAlpha(80)),
              const SizedBox(height: 16),
              Text('暂无点名记录', style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface.withAlpha(150))),
              const SizedBox(height: 8),
              Text('请在上方表单中添加第一条记录', style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withAlpha(100))),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 44,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 52,
            headingTextStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface),
            dataTextStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
            border: TableBorder.all(color: theme.dividerColor, width: 1, borderRadius: BorderRadius.circular(8)),
            columns: const [
              DataColumn(label: Text('时间')),
              DataColumn(label: Text('主控')),
              DataColumn(label: Text('呼号')),
              DataColumn(label: Text('RST发')),
              DataColumn(label: Text('RST收')),
              DataColumn(label: Text('QTH')),
              DataColumn(label: Text('设备')),
              DataColumn(label: Text('功率')),
              DataColumn(label: Text('天线')),
              DataColumn(label: Text('高度')),
              DataColumn(label: Text('操作')),
            ],
            rows: logs.reversed.map((log) {
              return DataRow(cells: [
                DataCell(SizedBox(width: 80, child: Text(log.time.length >= 16 ? log.time.substring(11, 16) : log.time))),
                DataCell(SizedBox(width: 100, child: Text(log.controller))),
                DataCell(SizedBox(width: 100, child: Text(log.callsign, style: const TextStyle(fontWeight: FontWeight.w600)))),
                DataCell(SizedBox(width: 70, child: Text(log.rstSent ?? ''))),
                DataCell(SizedBox(width: 70, child: Text(log.rstRcvd ?? ''))),
                DataCell(SizedBox(width: 120, child: Text(log.qth ?? ''))),
                DataCell(SizedBox(width: 120, child: Text(log.device ?? ''))),
                DataCell(SizedBox(width: 70, child: Text(log.power ?? ''))),
                DataCell(SizedBox(width: 120, child: Text(log.antenna ?? ''))),
                DataCell(SizedBox(width: 70, child: Text(log.height ?? ''))),
                DataCell(SizedBox(
                  width: 80,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(backgroundColor: theme.colorScheme.primary.withAlpha(26)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () => _deleteLog(context, log, session),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(backgroundColor: theme.colorScheme.error.withAlpha(26)),
                      ),
                    ],
                  ),
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _deleteLog(BuildContext context, LogEntry log, dynamic session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${log.callsign} 的记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (session != null) {
                context.read<RustLogProvider>().deleteLog(session.sessionId, log.syncId);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ─── Dictionary Page ────────────────────────────────────

class _DictPage extends StatelessWidget {
  const _DictPage();

  @override
  Widget build(BuildContext context) {
    final rdp = context.watch<RustDictProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          _dictCard(context, '设备词典', rdp.deviceDict),
          const SizedBox(height: 8),
          _dictCard(context, '天线词典', rdp.antennaDict),
          const SizedBox(height: 8),
          _dictCard(context, '呼号词典', rdp.callsignDict),
          const SizedBox(height: 8),
          _dictCard(context, 'QTH词典', rdp.qthDict),
        ],
      ),
    );
  }

  Widget _dictCard(BuildContext context, String title, List<DictItem> items) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text('暂无数据', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120)))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items.take(30).map((item) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item.raw, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                )).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Page ──────────────────────────────────────

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    final rsp = context.watch<RustSettingsProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
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
                    subtitle: const Text('1.0.0 · Rust Core'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
