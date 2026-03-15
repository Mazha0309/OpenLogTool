import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

class LogForm extends StatefulWidget {
  const LogForm({super.key});

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> {
  final _formKey = GlobalKey<FormState>();
  final _controllerController = TextEditingController();
  final _callsignController = TextEditingController();
  final _deviceController = TextEditingController();
  final _antennaController = TextEditingController();
  final _powerController = TextEditingController();
  final _qthController = TextEditingController();
  final _heightController = TextEditingController();
  final _timeController = TextEditingController();
  final _reportController = TextEditingController(text: '59');

  @override
  void initState() {
    super.initState();
    _loadEditingData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadEditingData();
  }

  void _loadEditingData() {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    if (logProvider.isEditing) {
      final log = logProvider.getLogForEditing();
      if (log != null) {
        _controllerController.text = log.controller;
        _callsignController.text = log.callsign;
        _deviceController.text = log.device;
        _antennaController.text = log.antenna;
        _powerController.text = log.power;
        _qthController.text = log.qth;
        _heightController.text = log.height;
        _timeController.text = log.time;
        _reportController.text = log.report;
      }
    }
  }

  @override
  void dispose() {
    _controllerController.dispose();
    _callsignController.dispose();
    _deviceController.dispose();
    _antennaController.dispose();
    _powerController.dispose();
    _qthController.dispose();
    _heightController.dispose();
    _timeController.dispose();
    _reportController.dispose();
    super.dispose();
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final logProvider = Provider.of<LogProvider>(context, listen: false);
      final dictionaryProvider = Provider.of<DictionaryProvider>(context, listen: false);

      // 自动添加到词典
      if (_deviceController.text.isNotEmpty) {
        await dictionaryProvider.addDevice(_deviceController.text);
      }
      if (_antennaController.text.isNotEmpty) {
        await dictionaryProvider.addAntenna(_antennaController.text);
      }
      if (_callsignController.text.isNotEmpty) {
        await dictionaryProvider.addCallsign(_callsignController.text);
      }
      if (_qthController.text.isNotEmpty) {
        await dictionaryProvider.addQth(_qthController.text);
      }

      final log = LogEntry(
        time: _timeController.text.isNotEmpty ? _timeController.text : _getCurrentTime(),
        controller: _controllerController.text.toUpperCase(),
        callsign: _callsignController.text.toUpperCase(),
        report: _reportController.text,
        qth: _qthController.text,
        device: _deviceController.text,
        power: _powerController.text,
        antenna: _antennaController.text,
        height: _heightController.text,
      );

      await logProvider.addLog(log);

      // 重置表单（如果不是编辑模式）
      if (!logProvider.isEditing) {
        _resetForm();
      } else {
        logProvider.cancelEditing();
      }

      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(logProvider.isEditing ? '记录已更新' : '记录已添加'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _controllerController.clear();
    _callsignController.clear();
    _deviceController.clear();
    _antennaController.clear();
    _powerController.clear();
    _qthController.clear();
    _heightController.clear();
    _timeController.clear();
    _reportController.text = '59';
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelEditing() {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.cancelEditing();
    _resetForm();
  }

  // 修复输入框文本转换问题
  void _handleTextChange(TextEditingController controller, String value, {bool toUpperCase = false}) {
    final selection = controller.selection;
    final newText = toUpperCase ? value.toUpperCase() : value;
    
    if (newText != controller.text) {
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.baseOffset + (newText.length - value.length)),
        composing: TextRange.empty,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);

    return Form(
      key: _formKey,
      child: Column(
        children: [
          // 第一行：主控呼号、点名呼号、设备
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _controllerController,
                  label: '主控呼号 *',
                  hintText: '输入主控呼号',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入主控呼号';
                    }
                    return null;
                  },
                  onChanged: (value) => _handleTextChange(_controllerController, value, toUpperCase: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAutocompleteField(
                  controller: _callsignController,
                  label: '点名呼号',
                  hintText: '输入呼号',
                  options: dictionaryProvider.callsignDict,
                  onChanged: (value) => _handleTextChange(_callsignController, value, toUpperCase: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAutocompleteField(
                  controller: _deviceController,
                  label: '设备',
                  hintText: '输入设备名称',
                  options: dictionaryProvider.deviceDict,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 第二行：天线、功率、QTH
          Row(
            children: [
              Expanded(
                child: _buildAutocompleteField(
                  controller: _antennaController,
                  label: '天线',
                  hintText: '输入天线名称',
                  options: dictionaryProvider.antennaDict,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _powerController,
                  label: '功率',
                  hintText: '输入功率',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAutocompleteField(
                  controller: _qthController,
                  label: 'QTH',
                  hintText: '输入QTH',
                  options: dictionaryProvider.qthDict,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 第三行：高度、时间、信号报告
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _heightController,
                  label: '高度',
                  hintText: '输入高度',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _timeController,
                  label: '时间',
                  hintText: 'HH:mm (留空使用当前时间)',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _reportController,
                  label: '信号报告',
                  hintText: '输入信号报告',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入信号报告';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(logProvider.isEditing ? Icons.save : Icons.add),
                  label: Text(logProvider.isEditing ? '更新记录' : '添加记录'),
                  onPressed: _submitForm,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (logProvider.isEditing) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('取消编辑'),
                  onPressed: _cancelEditing,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
        filled: true,
      ),
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required List<String> options,
    void Function(String)? onChanged,
  }) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return options.where((option) =>
            option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController fieldController,
        FocusNode fieldFocusNode,
        VoidCallback onFieldSubmitted,
      ) {
        return TextFormField(
          controller: fieldController,
          focusNode: fieldFocusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            border: const OutlineInputBorder(),
            filled: true,
          ),
          onChanged: onChanged,
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<String> onSelected,
        Iterable<String> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: SizedBox(
              height: 200.0,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return ListTile(
                    title: Text(option),
                    onTap: () {
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}