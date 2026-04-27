import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';

/// 日志表单组件
/// 用于添加和编辑点名记录
class LogForm extends StatefulWidget {
  const LogForm({super.key});

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey<_QthFieldWithHistoryState> _qthFieldKey = GlobalKey<_QthFieldWithHistoryState>();
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

    await logProvider.addLog(log);
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
                    child: _QthFieldWithHistory(
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
                child: ElevatedButton.icon(
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

class _QthFieldWithHistory extends StatefulWidget {
  final TextEditingController controller;
  final TextEditingController callsignController;
  final List<DictionaryItem> dictionaryOptions;
  final String label;
  final String hintText;
  final TextInputAction? textInputAction;
  final bool isCompact;

  const _QthFieldWithHistory({
    super.key,
    required this.controller,
    required this.callsignController,
    required this.dictionaryOptions,
    required this.label,
    required this.hintText,
    this.textInputAction,
    this.isCompact = false,
  });

  @override
  State<_QthFieldWithHistory> createState() => _QthFieldWithHistoryState();
}

class _QthFieldWithHistoryState extends State<_QthFieldWithHistory> {
  List<Map<String, dynamic>> _history = [];
  String _lastCallsign = '';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _focusNode = FocusNode();
  bool _isSelectingHistory = false; // 标志：是否正在选择历史记录

  @override
  void initState() {
    super.initState();
    _lastCallsign = widget.callsignController.text;
    widget.callsignController.addListener(_onCallsignChanged);
    _focusNode.addListener(_onFocusChanged);
    // 延迟加载历史记录，确保 context 已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _hideOverlay();
    widget.callsignController.removeListener(_onCallsignChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onCallsignChanged() {
    final newCallsign = widget.callsignController.text;
    _lastCallsign = newCallsign;
    _loadHistory();
    // 呼号变化时隐藏历史记录
    if (_overlayEntry != null) {
      _hideOverlay();
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // 当输入框获得焦点且为空时，显示历史记录
      if (widget.controller.text.isEmpty && 
          _history.isNotEmpty &&
          _overlayEntry == null) {
        _showOverlay();
      }
    } else {
      // 当输入框失去焦点时，延迟隐藏历史记录
      // 延迟是为了允许点击历史记录下拉框中的项目
      // 手机端需要更长的延迟
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_focusNode.hasFocus && 
            _overlayEntry != null && 
            !_isSelectingHistory) {
          _hideOverlay();
        }
      });
    }
  }

  Future<void> _loadHistory() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.callSignQthLinkEnabled || _lastCallsign.isEmpty) {
      if (mounted) {
        setState(() => _history = []);
      }
      _hideOverlay();
      return;
    }

    final db = DatabaseHelper();
    final history = await db.getCallsignQthHistory(_lastCallsign);
    
    if (mounted) {
      setState(() => _history = history);
      // 加载完成后，如果输入框有焦点且为空，显示历史记录
      if (_focusNode.hasFocus && 
          widget.controller.text.isEmpty && 
          _history.isNotEmpty &&
          _overlayEntry == null) {
        _showOverlay();
      }
    }
  }

  void refresh() {
    _loadHistory();
  }

  void _showOverlay() {
    _hideOverlay();
    if (_history.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withAlpha(128),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _lastCallsign.toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '的历史QTH',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outline.withAlpha(77),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final qth = item['qth'] as String;
                        final recordedAt = item['recorded_at'] as String?;

                        String subtitle;
                        if (recordedAt != null) {
                          final dt = DateTime.parse(recordedAt);
                          subtitle = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                        } else {
                          subtitle = '';
                        }

                        return Material(
                          color: Colors.transparent,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (_) {
                              // 标记正在选择历史记录，防止失去焦点时关闭
                              _isSelectingHistory = true;
                            },
                            onPointerUp: (_) {
                              widget.controller.text = qth;
                              _isSelectingHistory = false;
                              _hideOverlay();
                            },
                            child: InkWell(
                              onTap: () {
                                // 备用：如果 Listener 没触发，这里也处理
                                widget.controller.text = qth;
                                _isSelectingHistory = false;
                                _hideOverlay();
                              },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: index < _history.length - 1
                                  ? Border(
                                      bottom: BorderSide(
                                        color: Theme.of(context).colorScheme.outline.withAlpha(51),
                                        width: 1,
                                      ),
                                    )
                                  : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary.withAlpha(179),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          qth,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty)
                                          Text(
                                            subtitle,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        // 点击组件外部时隐藏历史记录
        if (_overlayEntry != null) {
          _hideOverlay();
        }
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Autocomplete<DictionaryItem>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<DictionaryItem>.empty();
          }
          return widget.dictionaryOptions.where((option) =>
              option.matches(textEditingValue.text));
        },
        onSelected: (DictionaryItem selection) {
          widget.controller.text = selection.raw;
          _hideOverlay();
        },
        fieldViewBuilder: (
          BuildContext context,
          TextEditingController fieldController,
          FocusNode fieldFocusNode,
          VoidCallback onFieldSubmitted,
        ) {
          // 同步外部controller的变化
          widget.controller.addListener(() {
            if (fieldController.text != widget.controller.text) {
              fieldController.text = widget.controller.text;
            }
          });

          return TextFormField(
            controller: fieldController,
            focusNode: fieldFocusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.isCompact ? 10 : 14),
            ),
            onTap: () {
              // 点击输入框时，如果为空且有历史记录，显示历史记录
              if (fieldController.text.isEmpty && _history.isNotEmpty && _overlayEntry == null) {
                _showOverlay();
              }
            },
            onChanged: (value) {
              widget.controller.text = value;
              // 输入时隐藏历史记录
              if (_overlayEntry != null) {
                _hideOverlay();
              }
            },
            textInputAction: widget.textInputAction ?? TextInputAction.next,
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
      ),
      ),
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
