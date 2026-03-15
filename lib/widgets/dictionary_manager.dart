import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';

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
    _controllers.values.forEach((controller) => controller.dispose());
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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final content = String.fromCharCodes(file.bytes!);
        final lines = content.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();

        final provider = Provider.of<DictionaryProvider>(context, listen: false);
        
        switch (dictType) {
          case 'device':
            await provider.importDevices(lines);
            break;
          case 'antenna':
            await provider.importAntennas(lines);
            break;
          case 'callsign':
            await provider.importCallsigns(lines);
            break;
          case 'qth':
            await provider.importQths(lines);
            break;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导入 ${lines.length} 条${_getDictName(dictType)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
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

  Widget _buildDictionaryCard({
    required String type,
    required String title,
    required List<String> items,
    required Function(String) onAdd,
  }) {
    return Card(
      elevation: 2,
      child: ExpansionPanelList(
        elevation: 0,
        expandedHeaderPadding: EdgeInsets.zero,
        expansionCallback: (int index, bool isExpanded) {
          _toggleDictionary(type);
        },
        children: [
          ExpansionPanel(
            headerBuilder: (context, isExpanded) {
              return ListTile(
                title: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            },
            body: Padding(
              padding: const EdgeInsets.all(16.0),
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
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('添加'),
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

                  const SizedBox(height: 16),

                  // 导入文件按钮
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('从文件导入'),
                    onPressed: () => _importFromFile(type),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 项目列表
                  if (items.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(items[index]),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '暂无${_getDictName(type)}数据',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            isExpanded: _expandedStates[type]!,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);
    final allExpanded = _expandedStates.values.every((state) => state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题和切换按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '词库管理器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              icon: Icon(allExpanded ? Icons.expand_less : Icons.expand_more),
              label: Text(allExpanded ? '折叠全部' : '展开全部'),
              onPressed: _toggleAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 设备词典
        _buildDictionaryCard(
          type: 'device',
          title: '设备词典管理',
          items: dictionaryProvider.deviceDict,
          onAdd: (value) async {
            await dictionaryProvider.addDevice(value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加设备: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // 天线词典
        _buildDictionaryCard(
          type: 'antenna',
          title: '天线词典管理',
          items: dictionaryProvider.antennaDict,
          onAdd: (value) async {
            await dictionaryProvider.addAntenna(value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加天线: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // 呼号词典
        _buildDictionaryCard(
          type: 'callsign',
          title: '呼号词典管理',
          items: dictionaryProvider.callsignDict,
          onAdd: (value) async {
            await dictionaryProvider.addCallsign(value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加呼号: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // QTH词典
        _buildDictionaryCard(
          type: 'qth',
          title: 'QTH词典管理',
          items: dictionaryProvider.qthDict,
          onAdd: (value) async {
            await dictionaryProvider.addQth(value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已添加QTH: $value'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}