import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

/// 日志表单组件
/// 用于添加和编辑点名记录
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

  String? _controllerError;
  String? _reportError;

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

  bool _validateForm() {
    bool isValid = true;
    if (_controllerController.text.isEmpty) {
      setState(() => _controllerError = '请输入主控呼号');
      isValid = false;
    } else {
      setState(() => _controllerError = null);
    }
    if (_reportController.text.isEmpty) {
      setState(() => _reportError = '请输入信号报告');
      isValid = false;
    } else {
      setState(() => _reportError = null);
    }
    return isValid;
  }

  Future<void> _submitForm() async {
    if (!_validateForm()) return;

    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final dictionaryProvider = Provider.of<DictionaryProvider>(context, listen: false);

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

    final isEditing = logProvider.isEditing;
    logProvider.addLog(log);
    _resetForm();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? '记录已更新' : '记录已添加'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetForm() {
    _callsignController.clear();
    _deviceController.clear();
    _antennaController.clear();
    _powerController.clear();
    _qthController.clear();
    _heightController.clear();
    _timeController.clear();
    _reportController.text = '59';
    setState(() {
      _controllerError = null;
      _reportError = null;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelEditing() {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.cancelEditing();
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度计算每行显示几个字段
        final availableWidth = constraints.maxWidth;
        final fieldWidth = 200.0;
        final spacing = 12.0;
        final fieldsPerRow = ((availableWidth + spacing) / (fieldWidth + spacing)).floor().clamp(1, 5);
        final calculatedFieldWidth = (availableWidth - (spacing * (fieldsPerRow - 1))) / fieldsPerRow;

        return Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 使用 Wrap 实现响应式自动换行布局，输入框会根据可用空间自动调整宽度
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                alignment: WrapAlignment.start,
                children: [
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _controllerController,
                      label: '主控呼号 *',
                      hintText: '输入主控呼号',
                      error: _controllerError,
                      onChanged: (value) {
                        if (_controllerError != null) {
                          setState(() => _controllerError = null);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _callsignController,
                      label: '点名呼号',
                      hintText: '输入呼号',
                      options: dictionaryProvider.callsignDict,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _deviceController,
                      label: '设备',
                      hintText: '输入设备名称',
                      options: dictionaryProvider.deviceDict,
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _antennaController,
                      label: '天线',
                      hintText: '输入天线名称',
                      options: dictionaryProvider.antennaDict,
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _powerController,
                      label: '功率',
                      hintText: '输入功率',
                      keyboardType: TextInputType.number,
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _qthController,
                      label: 'QTH',
                      hintText: '输入QTH',
                      options: dictionaryProvider.qthDict,
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _heightController,
                      label: '高度',
                      hintText: '输入高度',
                      keyboardType: TextInputType.number,
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _timeController,
                      label: '时间',
                      hintText: 'HH:mm (留空使用当前时间)',
                      upperCase: false,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _reportController,
                      label: '信号报告',
                      hintText: '输入信号报告',
                      error: _reportError,
                      onChanged: (value) {
                        if (_reportError != null) {
                          setState(() => _reportError = null);
                        }
                      },
                      upperCase: false,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 操作按钮 - 占满宽度
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submitForm,
                      icon: Icon(logProvider.isEditing ? Icons.save : Icons.add),
                      label: Text(logProvider.isEditing ? '更新记录' : '添加记录'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (logProvider.isEditing) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cancelEditing,
                        icon: const Icon(Icons.cancel),
                        label: const Text('取消编辑'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMaterialTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType? keyboardType,
    String? error,
    void Function(String)? onChanged,
    bool upperCase = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: error,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      keyboardType: keyboardType,
      onChanged: onChanged,
      textCapitalization: upperCase ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: upperCase ? [UpperCaseTextFormatter()] : [],
    );
  }

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required List<String> options,
    void Function(String)? onChanged,
    bool upperCase = true,
  }) {
    final textCapitalization = upperCase ? TextCapitalization.characters : TextCapitalization.none;
    final inputFormatters = upperCase ? [UpperCaseTextFormatter()] : <TextInputFormatter>[];

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
        controller.addListener(() {
          if (fieldController.text != controller.text) {
            fieldController.text = controller.text;
          }
        });
        return TextFormField(
          controller: fieldController,
          focusNode: fieldFocusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          onChanged: (value) {
            controller.text = upperCase ? value.toUpperCase() : value;
            onChanged?.call(value);
          },
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
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
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 200.0,
              width: 200,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return ListTile(
                    title: Text(option),
                    onTap: () => onSelected(option),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
