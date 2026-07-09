import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/models/dictionary_item.dart';

class DictionaryManager extends StatefulWidget {
  const DictionaryManager({super.key});

  @override
  State<DictionaryManager> createState() => _DictionaryManagerState();
}

class _DictionaryManagerState extends State<DictionaryManager> {
  final Map<String, bool> _expandedStates = {
    'device': false,
    'antenna': false,
    'callsign': false,
    'qth': false,
  };

  final Map<String, TextEditingController> _controllers = {
    'device': TextEditingController(),
    'antenna': TextEditingController(),
    'callsign': TextEditingController(),
    'qth': TextEditingController(),
  };

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggleAll() {
    final allExpanded = _expandedStates.values.every((state) => state);
    setState(() {
      _expandedStates.forEach((key, value) {
        _expandedStates[key] = !allExpanded;
      });
    });
  }

  void _toggleDictionary(String key) {
    setState(() {
      _expandedStates[key] = !_expandedStates[key]!;
    });
  }

  Future<void> _importFromFile(String dictType) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<DictionaryProvider>(context, listen: false);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final content = String.fromCharCodes(file.bytes!);
        final counts = await provider.importFromJson(content);

        final total = counts.values.fold(0, (a, b) => a + b);
        if (total == 0) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('文件中没有可导入的词库数据'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        final parts = <String>[];
        counts.forEach((key, count) {
          parts.add('${_getDictName(key)} $count 条');
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('已导入：${parts.join('，')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('导入失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getDictName(String type) {
    switch (type) {
      case 'device':
        return '设备';
      case 'antenna':
        return '天线';
      case 'callsign':
        return '呼号';
      case 'qth':
        return 'QTH';
      default:
        return '';
    }
  }

  IconData _getDictIcon(String type) {
    switch (type) {
      case 'device':
        return Icons.radio;
      case 'antenna':
        return Icons.settings_input_antenna;
      case 'callsign':
        return Icons.badge;
      case 'qth':
        return Icons.place;
      default:
        return Icons.folder;
    }
  }

  Widget _buildDictionaryCard({
    required String type,
    required String title,
    required List<DictionaryItem> items,
    required Function(String) onAdd,
    double cardPadding = 16.0,
  }) {
    final theme = Theme.of(context);
    final isExpanded = _expandedStates[type]!;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleDictionary(type),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: cardPadding,
                vertical: cardPadding * 0.75,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getDictIcon(type),
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '共 ${items.length} 条',
                          style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(
                cardPadding,
                0,
                cardPadding,
                cardPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 添加项目表单
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllers[type],
                          decoration: InputDecoration(
                            labelText: '添加${_getDictName(type)}',
                            hintText: '输入${_getDictName(type)}名称',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              onAdd(value);
                              _controllers[type]!.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () {
                          final value = _controllers[type]!.text.trim();
                          if (value.isNotEmpty) {
                            onAdd(value);
                            _controllers[type]!.clear();
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 导入文件按钮
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload, size: 18),
                    label: const Text('从文件导入 (.json)'),
                    onPressed: () => _importFromFile(type),
                  ),

                  const SizedBox(height: 16),

                  // 项目列表
                  if (items.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Text(
                              '${index + 1}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            title: Text(
                              item.raw,
                              style: theme.textTheme.bodyMedium,
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 32,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withAlpha(180),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '暂无${_getDictName(type)}数据',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);
    final allExpanded = _expandedStates.values.every((state) => state);
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final cardSpacing = isNarrow ? 12.0 : 16.0;
    final cardPadding = isNarrow ? 12.0 : 16.0;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题和切换按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '词库管理器',
              style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton.icon(
              icon: Icon(
                allExpanded ? Icons.unfold_less : Icons.unfold_more,
                size: 18,
              ),
              label: Text(allExpanded ? '折叠全部' : '展开全部'),
              onPressed: _toggleAll,
            ),
          ],
        ),

        SizedBox(height: cardSpacing),

        // 设备词典
        _buildDictionaryCard(
          type: 'device',
          title: '设备词典管理',
          items: dictionaryProvider.deviceDict,
          cardPadding: cardPadding,
          onAdd: (value) async {
            final messenger = ScaffoldMessenger.of(context);
            await dictionaryProvider.addDevice(value);
            messenger.showSnackBar(
              SnackBar(
                content: Text('已添加设备: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        SizedBox(height: cardSpacing),

        // 天线词典
        _buildDictionaryCard(
          type: 'antenna',
          title: '天线词典管理',
          items: dictionaryProvider.antennaDict,
          cardPadding: cardPadding,
          onAdd: (value) async {
            final messenger = ScaffoldMessenger.of(context);
            await dictionaryProvider.addAntenna(value);
            messenger.showSnackBar(
              SnackBar(
                content: Text('已添加天线: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        SizedBox(height: cardSpacing),

        // 呼号词典
        _buildDictionaryCard(
          type: 'callsign',
          title: '呼号词典管理',
          items: dictionaryProvider.callsignDict,
          cardPadding: cardPadding,
          onAdd: (value) async {
            final messenger = ScaffoldMessenger.of(context);
            await dictionaryProvider.addCallsign(value);
            messenger.showSnackBar(
              SnackBar(
                content: Text('已添加呼号: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        SizedBox(height: cardSpacing),

        // QTH词典
        _buildDictionaryCard(
          type: 'qth',
          title: 'QTH 词典管理',
          items: dictionaryProvider.qthDict,
          cardPadding: cardPadding,
          onAdd: (value) async {
            final messenger = ScaffoldMessenger.of(context);
            await dictionaryProvider.addQth(value);
            messenger.showSnackBar(
              SnackBar(
                content: Text('已添加 QTH: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}
