import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/qth_field_with_history.dart';

/// 日志表单组件
/// 用于添加和编辑点名记录
class LogForm extends StatefulWidget {
  const LogForm({super.key});

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
final GlobalKey<QthFieldWithHistoryState> _qthFieldKey =
      GlobalKey<QthFieldWithHistoryState>();
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
  bool get wantKeepAlive => true;

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
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
    final dictionaryProvider = Provider.of<DictionaryProvider>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

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
      if (settingsProvider.callSignQthLinkEnabled) {
        await DatabaseHelper().addCallsignQthRecord(_callsignController.text, _qthController.text);
      }
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

    await logProvider.addLog(log, sessionId: sessionProvider.currentSessionId);
    _resetForm();
    _qthFieldKey.currentState?.refresh();

    if (context.mounted) {
        context.showLoggedSnackBar(
          const SnackBar(
            content: Text('记录已添加'),
            duration: Duration(seconds: 2),
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

  @override
  Widget build(BuildContext context) {
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度计算每行显示几个字段
        final availableWidth = constraints.maxWidth;
        final isNarrow = availableWidth < 600;
        final fieldWidth = isNarrow ? 160.0 : 200.0;
        final spacing = isNarrow ? 8.0 : 12.0;
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
                runSpacing: isNarrow ? 8 : spacing,
                alignment: WrapAlignment.start,
                children: [
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _controllerController,
                      label: '主控呼号 *',
                      hintText: '输入主控呼号',
                      error: _controllerError,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        if (_controllerError != null) {
                          setState(() => _controllerError = null);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildCallsignFieldWithQthLink(
                      controller: _callsignController,
                      qthController: _qthController,
                      dictionaryOptions: dictionaryProvider.callsignDict,
                      label: '点名呼号',
                      hintText: '输入呼号',
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
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
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
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
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
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
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: QthFieldWithHistory(
                      key: _qthFieldKey,
                      controller: _qthController,
                      callsignController: _callsignController,
                      dictionaryOptions: dictionaryProvider.qthDict,
                      label: 'QTH',
                      hintText: '输入QTH',
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
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
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _timeController,
                      label: '时间',
                      hintText: 'HH:mm',
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
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
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitForm(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 操作按钮 - 占满宽度
              SizedBox(
                height: isNarrow ? 44 : 48,
                child: FilledButton.icon(
                  onPressed: _submitForm,
                  icon: const Icon(Icons.add),
                  label: const Text('添加记录'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: isNarrow ? 10 : 14),
                  ),
                ),
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
    void Function(String)? onSubmitted,
    TextInputAction? textInputAction,
    bool upperCase = true,
    bool isCompact = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: error,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 10 : 14),
      ),
      keyboardType: keyboardType,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction ?? TextInputAction.next,
      textCapitalization: upperCase ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: upperCase ? [UpperCaseTextFormatter()] : [],
    );
  }

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required List<DictionaryItem> options,
    void Function(String)? onChanged,
    TextInputAction? textInputAction,
    bool upperCase = true,
    bool isCompact = false,
  }) {
    final textCapitalization = upperCase ? TextCapitalization.characters : TextCapitalization.none;
    final inputFormatters = upperCase ? [UpperCaseTextFormatter()] : <TextInputFormatter>[];

    return Autocomplete<DictionaryItem>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<DictionaryItem>.empty();
        }
        return options.where((option) =>
            option.matches(textEditingValue.text));
      },
      onSelected: (DictionaryItem selection) {
        controller.text = selection.raw;
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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 10 : 14),
          ),
          onChanged: (value) {
            controller.text = upperCase ? value.toUpperCase() : value;
            onChanged?.call(value);
          },
          textInputAction: textInputAction ?? TextInputAction.next,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<DictionaryItem> onSelected,
        Iterable<DictionaryItem> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final DictionaryItem item = options.elementAt(index);
                  return ListTile(
                    title: Text(item.raw),
                    dense: true,
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallsignFieldWithQthLink({
    required TextEditingController controller,
    required TextEditingController qthController,
    required List<DictionaryItem> dictionaryOptions,
    required String label,
    required String hintText,
    TextInputAction? textInputAction,
    bool isCompact = false,
  }) {
    return Autocomplete<DictionaryItem>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<DictionaryItem>.empty();
        }
        return dictionaryOptions.where((option) =>
            option.matches(textEditingValue.text));
      },
      onSelected: (DictionaryItem selection) {
        controller.text = selection.raw;
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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 10 : 14),
          ),
          onChanged: (value) {
            controller.text = value.toUpperCase();
          },
          textInputAction: textInputAction ?? TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<DictionaryItem> onSelected,
        Iterable<DictionaryItem> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final DictionaryItem item = options.elementAt(index);
                  return ListTile(
                    title: Text(item.raw),
                    dense: true,
                    onTap: () => onSelected(item),
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
