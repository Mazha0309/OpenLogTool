import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/utils/log_time.dart';
import 'package:openlogtool/widgets/callsign_history_field.dart';

/// 日志表单组件
/// 用于添加和编辑点名记录
class LogForm extends StatefulWidget {
  const LogForm({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _controllerController = TextEditingController();
  final _callsignController = TextEditingController();
  final FocusNode _callsignFocusNode = FocusNode();
  final _deviceController = TextEditingController();
  final _antennaController = TextEditingController();
  final _powerController = TextEditingController();
  final _qthController = TextEditingController();
  final _heightController = TextEditingController();
  final _timeController = TextEditingController();
  final _reportController = TextEditingController();
  final _rstRcvdController = TextEditingController();
  final _remarksController = TextEditingController();
  final Map<String, Timer> _draftDebounce = {};
  late final Map<String, TextEditingController> _draftControllers;
  late final Map<String, FocusNode> _draftFocusNodes;
  late final Map<String, VoidCallback> _draftControllerListeners;
  late final Map<String, VoidCallback> _draftFocusListeners;
  final Set<String> _focusedDraftFields = <String>{};
  Timer? _lockExpiryTimer;
  bool _applyingSharedDraft = false;
  String? _lastSharedDraftSignature;
  String? _lastSharedDraftId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reportController.text = '59';
    _rstRcvdController.text = '59';
    _draftControllers = {
      'time': _timeController,
      'controller': _controllerController,
      'callsign': _callsignController,
      'rstSent': _reportController,
      'rstRcvd': _rstRcvdController,
      'qth': _qthController,
      'device': _deviceController,
      'power': _powerController,
      'antenna': _antennaController,
      'height': _heightController,
      'remarks': _remarksController,
    };
    _draftFocusNodes = {
      for (final field in _draftControllers.keys)
        field: field == 'callsign' ? _callsignFocusNode : FocusNode(),
    };
    _draftControllerListeners = {
      for (final field in _draftControllers.keys)
        field: () => _onDraftFieldChanged(field),
    };
    _draftFocusListeners = {
      for (final field in _draftFocusNodes.keys)
        field: () => _onDraftFocusChanged(field),
    };
    for (final entry in _draftControllers.entries) {
      entry.value.addListener(_draftControllerListeners[entry.key]!);
    }
    for (final entry in _draftFocusNodes.entries) {
      entry.value.addListener(_draftFocusListeners[entry.key]!);
    }
  }

  @override
  void dispose() {
    _lockExpiryTimer?.cancel();
    for (final timer in _draftDebounce.values) {
      timer.cancel();
    }
    for (final entry in _draftControllers.entries) {
      entry.value.removeListener(_draftControllerListeners[entry.key]!);
    }
    for (final entry in _draftFocusNodes.entries) {
      entry.value.removeListener(_draftFocusListeners[entry.key]!);
      if (entry.key != 'callsign') entry.value.dispose();
    }
    _controllerController.dispose();
    _callsignController.dispose();
    _callsignFocusNode.dispose();
    _deviceController.dispose();
    _antennaController.dispose();
    _powerController.dispose();
    _qthController.dispose();
    _heightController.dispose();
    _timeController.dispose();
    _reportController.dispose();
    _rstRcvdController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _syncSharedDraft(CollaborationProvider collaboration) {
    final snapshot = collaboration.liveDraftSnapshot;
    final fields = collaboration.liveDraftFields;
    if (snapshot == null || fields == null) {
      _lastSharedDraftId = null;
      _lastSharedDraftSignature = null;
      return;
    }
    final signature = '${snapshot.draft.draftId}:${snapshot.draft.version}:'
        '${fields.toJson()}';
    if (_lastSharedDraftSignature == signature) return;
    final draftChanged = _lastSharedDraftId != snapshot.draft.draftId;
    _lastSharedDraftId = snapshot.draft.draftId;
    _lastSharedDraftSignature = signature;
    _applyingSharedDraft = true;
    try {
      for (final entry in _draftControllers.entries) {
        if (!draftChanged && _focusedDraftFields.contains(entry.key)) continue;
        final rawValue = fields[entry.key];
        final value =
            entry.key == 'time' ? _displayLiveDraftTime(rawValue) : rawValue;
        if (entry.value.text == value) continue;
        entry.value.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    } finally {
      _applyingSharedDraft = false;
    }
  }

  void _onDraftFieldChanged(String field) {
    if (_applyingSharedDraft || !mounted) return;
    final collaboration = context.read<CollaborationProvider>();
    if (collaboration.liveDraftSnapshot == null ||
        !collaboration.canEditLiveDraft) {
      return;
    }
    _draftDebounce.remove(field)?.cancel();
    _draftDebounce[field] = Timer(const Duration(milliseconds: 250), () {
      _draftDebounce.remove(field);
      if (!mounted) return;
      unawaited(
        collaboration
            .updateLiveDraftField(field, _draftControllers[field]!.text)
            .catchError((Object _) {}),
      );
    });
  }

  void _onDraftFocusChanged(String field) {
    if (!mounted) return;
    final collaboration = context.read<CollaborationProvider>();
    if (collaboration.liveDraftSnapshot == null) return;
    final focused = _draftFocusNodes[field]?.hasFocus ?? false;
    focused
        ? _focusedDraftFields.add(field)
        : _focusedDraftFields.remove(field);
    if (focused && collaboration.canEditLiveDraft) {
      unawaited(_acquireDraftField(field, collaboration));
      return;
    }
    if (!focused) unawaited(_flushAndReleaseDraftField(field, collaboration));
  }

  Future<void> _acquireDraftField(
    String field,
    CollaborationProvider collaboration,
  ) async {
    try {
      await collaboration.acquireLiveDraftField(field);
    } catch (_) {
      // Refreshing exposes the holder and disables the field after a lock race.
      try {
        await collaboration.refreshLiveDraft();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Future<void> _flushAndReleaseDraftField(
    String field,
    CollaborationProvider collaboration,
  ) async {
    _draftDebounce.remove(field)?.cancel();
    if (collaboration.canEditLiveDraft) {
      try {
        await collaboration.updateLiveDraftField(
          field,
          _draftControllers[field]!.text,
        );
      } catch (_) {
        // The provider exposes the protocol error and retains the local value.
      }
    }
    await collaboration.releaseLiveDraftField(field);
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _displayLiveDraftTime(String value) {
    return formatLogTimeForDisplay(value);
  }

  Future<void> _submitForm() async {
    final collaboration = context.read<CollaborationProvider>();
    if (widget.readOnly ||
        (collaboration.liveDraftSnapshot != null &&
            !collaboration.canEditLiveDraft)) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final sessionProvider =
        Provider.of<SessionProvider>(context, listen: false);
    final dictionaryProvider =
        Provider.of<DictionaryProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final normalizedCallsign = _callsignController.text.trim().toUpperCase();
    final duplicate = normalizedCallsign.isNotEmpty &&
        logProvider.logs.any(
          (log) => log.callsign.trim().toUpperCase() == normalizedCallsign,
        );
    if (settingsProvider.duplicateCallsignWarningEnabled && duplicate) {
      final proceed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(l10n.duplicateCallsignTitle),
              content: Text(
                l10n.duplicateCallsignMessage(normalizedCallsign),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(l10n.saveAnyway),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed || !mounted) return;
    }

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
    if (!mounted) return;

    if (collaboration.liveDraftSnapshot != null) {
      if (_timeController.text.isEmpty) {
        _timeController.text = _getCurrentTime();
      }
      for (final timer in _draftDebounce.values) {
        timer.cancel();
      }
      _draftDebounce.clear();
      for (final entry in _draftControllers.entries) {
        try {
          await collaboration.updateLiveDraftField(
            entry.key,
            entry.value.text,
          );
        } catch (_) {
          // commitCurrentLiveDraft retries retained dirty values and decides
          // whether a network failure should enter the offline review queue.
        }
      }
      final disposition = await collaboration.commitCurrentLiveDraft();
      if (!mounted) return;
      _syncSharedDraft(collaboration);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            disposition == LiveDraftCommitDisposition.committed
                ? l10n.recordAdded
                : l10n.recordQueuedOffline,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      FocusScope.of(context).requestFocus(_callsignFocusNode);
      return;
    }

    final log = LogEntry(
      time: _timeController.text.isNotEmpty
          ? _timeController.text
          : _getCurrentTime(),
      controller: _controllerController.text.toUpperCase(),
      callsign: _callsignController.text.toUpperCase(),
      report: _reportController.text,
      rstRcvd: _rstRcvdController.text,
      qth: _qthController.text,
      device: _deviceController.text,
      power: _powerController.text,
      antenna: _antennaController.text,
      height: _heightController.text,
    );
    log.remarks = _remarksController.text;

    await logProvider.addLog(log, sessionId: sessionProvider.currentSessionId);
    if (!mounted) return;
    _resetForm();

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.recordAdded),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetForm() {
    // 主控呼号在连续添加时应保留，先保存再恢复。
    final controllerCallsign = _controllerController.text;
    _formKey.currentState?.reset();
    _controllerController.text = controllerCallsign;
    _callsignController.clear();
    _deviceController.clear();
    _antennaController.clear();
    _powerController.clear();
    _qthController.clear();
    _heightController.clear();
    _timeController.clear();
    _reportController.text = '59';
    _rstRcvdController.text = '59';
    _remarksController.clear();
    FocusScope.of(context).requestFocus(_callsignFocusNode);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dictionaryProvider = Provider.of<DictionaryProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final collaboration = Provider.of<CollaborationProvider>(context);
    _syncSharedDraft(collaboration);
    final sharedDraft = collaboration.liveDraftSnapshot != null;
    final readOnly =
        widget.readOnly || (sharedDraft && !collaboration.canEditLiveDraft);

    bool isActiveForeignLock(String field) {
      final lock = collaboration.lockForField(field);
      return lock != null &&
          lock.expiresAt.isAfter(DateTime.now()) &&
          collaboration.fieldLockedByAnotherUser(field);
    }

    final activeForeignLocks = collaboration.liveDraftLocks
        .where(
          (lock) =>
              lock.expiresAt.isAfter(DateTime.now()) &&
              collaboration.fieldLockedByAnotherUser(lock.field),
        )
        .toList(growable: false);
    _scheduleLockExpiryRefresh(activeForeignLocks);
    final firstForeignLock =
        activeForeignLocks.isEmpty ? null : activeForeignLocks.first;
    final canSubmit = !readOnly && firstForeignLock == null;

    bool fieldEnabled(String field) => !readOnly && !isActiveForeignLock(field);

    String fieldLabel(String field, String fallback) {
      final lock = collaboration.lockForField(field);
      if (lock == null || !isActiveForeignLock(field)) {
        return fallback;
      }
      return '$fallback · ${context.l10n.fieldLockedBy(lock.username)}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度计算每行显示几个字段
        final availableWidth = constraints.maxWidth;
        final isNarrow = availableWidth < 600;
        final fieldWidth = isNarrow ? 160.0 : 200.0;
        final spacing = isNarrow ? 8.0 : 12.0;
        final fieldsPerRow =
            ((availableWidth + spacing) / (fieldWidth + spacing))
                .floor()
                .clamp(1, 5);
        final calculatedFieldWidth =
            (availableWidth - (spacing * (fieldsPerRow - 1))) / fieldsPerRow;

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
                      label: fieldLabel('controller', '主控呼号 *'),
                      hintText: '输入主控呼号',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入主控呼号';
                        }
                        return null;
                      },
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['controller'],
                      enabled: fieldEnabled('controller'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: CallsignHistoryField(
                      callsignController: _callsignController,
                      deviceController: _deviceController,
                      antennaController: _antennaController,
                      qthController: _qthController,
                      powerController: _powerController,
                      heightController: _heightController,
                      reportController: _reportController,
                      rstRcvdController: _rstRcvdController,
                      timeController: _timeController,
                      controllerController: _controllerController,
                      label: fieldLabel('callsign', '点名呼号'),
                      hintText: '输入呼号',
                      focusNode: _callsignFocusNode,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      enabled: fieldEnabled('callsign'),
                      historyEnabled: settingsProvider.callSignQthLinkEnabled,
                      canFillField: fieldEnabled,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return context.l10n.callsignRequired;
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _deviceController,
                      label: fieldLabel('device', '设备'),
                      hintText: '输入设备名称',
                      options: dictionaryProvider.deviceDict,
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      draftField: 'device',
                      enabled: fieldEnabled('device'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _antennaController,
                      label: fieldLabel('antenna', '天线'),
                      hintText: '输入天线名称',
                      options: dictionaryProvider.antennaDict,
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      draftField: 'antenna',
                      enabled: fieldEnabled('antenna'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _powerController,
                      label: fieldLabel('power', '功率'),
                      hintText: '输入功率',
                      keyboardType: TextInputType.number,
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['power'],
                      enabled: fieldEnabled('power'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildAutocompleteField(
                      controller: _qthController,
                      label: fieldLabel('qth', 'QTH'),
                      hintText: '输入QTH',
                      options: dictionaryProvider.qthDict,
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      draftField: 'qth',
                      enabled: fieldEnabled('qth'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _heightController,
                      label: fieldLabel('height', '高度'),
                      hintText: '输入高度',
                      keyboardType: TextInputType.number,
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['height'],
                      enabled: fieldEnabled('height'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _timeController,
                      label: fieldLabel('time', '时间'),
                      hintText: 'HH:mm',
                      upperCase: false,
                      validator: (value) => isValidLogTimeInput(
                        value ?? '',
                        allowEmpty: true,
                      )
                          ? null
                          : context.l10n.logTimeInvalid,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['time'],
                      enabled: fieldEnabled('time'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _reportController,
                      label: fieldLabel('rstSent', 'RST发'),
                      hintText: '59',
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['rstSent'],
                      enabled: fieldEnabled('rstSent'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _rstRcvdController,
                      label: fieldLabel('rstRcvd', 'RST收'),
                      hintText: '59',
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.done,
                      onSubmitted: canSubmit ? (_) => _submitForm() : null,
                      focusNode: _draftFocusNodes['rstRcvd'],
                      enabled: fieldEnabled('rstRcvd'),
                    ),
                  ),
                  SizedBox(
                    width: calculatedFieldWidth,
                    child: _buildMaterialTextField(
                      controller: _remarksController,
                      label: fieldLabel('remarks', '备注'),
                      hintText: '可选备注',
                      upperCase: false,
                      isCompact: isNarrow,
                      textInputAction: TextInputAction.next,
                      focusNode: _draftFocusNodes['remarks'],
                      enabled: fieldEnabled('remarks'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 操作按钮 - 占满宽度
              SizedBox(
                height: isNarrow ? 44 : 48,
                child: FilledButton.icon(
                  onPressed: canSubmit ? _submitForm : null,
                  icon: Icon(
                    readOnly || firstForeignLock != null
                        ? Icons.lock_outline
                        : Icons.add,
                  ),
                  label: Text(
                    readOnly
                        ? context.l10n.sharedDraftReadOnly
                        : firstForeignLock != null
                            ? context.l10n.fieldLockedBy(
                                firstForeignLock.username,
                              )
                            : context.l10n.saveRecord,
                  ),
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
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    TextInputAction? textInputAction,
    bool upperCase = true,
    bool isCompact = false,
    FocusNode? focusNode,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: error,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 10 : 14),
      ),
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction ?? TextInputAction.next,
      textCapitalization:
          upperCase ? TextCapitalization.characters : TextCapitalization.none,
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
    required String draftField,
    bool enabled = true,
  }) {
    final textCapitalization =
        upperCase ? TextCapitalization.characters : TextCapitalization.none;
    final inputFormatters =
        upperCase ? [UpperCaseTextFormatter()] : <TextInputFormatter>[];

    final draftFocusNode = _draftFocusNodes[draftField]!;
    final autocomplete = Autocomplete<DictionaryItem>(
      textEditingController: controller,
      focusNode: draftFocusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<DictionaryItem>.empty();
        }
        final query = textEditingValue.text.toLowerCase();
        final scored = <_ScoredOption>[];
        for (final option in options) {
          if (!option.matches(textEditingValue.text)) continue;
          var score = 0;
          final raw = option.raw.toLowerCase();
          final pinyin = option.pinyin.toLowerCase();
          final abbr = option.abbreviation.toLowerCase();
          if (abbr.startsWith(query)) {
            score += 1000;
          } else if (abbr.contains(query)) {
            score += 500;
          }
          if (raw.startsWith(query)) {
            score += 300;
          } else if (raw.contains(query)) {
            score += 100;
          }
          if (pinyin.startsWith(query)) {
            score += 200;
          } else if (pinyin.contains(query)) {
            score += 50;
          }
          scored.add(_ScoredOption(option, score));
        }
        scored.sort((a, b) {
          if (b.score != a.score) return b.score.compareTo(a.score);
          return a.option.raw.compareTo(b.option.raw);
        });
        return scored.take(20).map((s) => s.option);
      },
      displayStringForOption: (option) => option.raw,
      onSelected: (DictionaryItem selection) {
        controller.text = selection.raw;
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
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
                horizontal: 12, vertical: isCompact ? 10 : 14),
          ),
          onChanged: (value) {
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
        final theme = Theme.of(context);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final DictionaryItem item = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(item.raw),
                    subtitle:
                        item.abbreviation.isNotEmpty || item.pinyin.isNotEmpty
                            ? Text(
                                [
                                  if (item.abbreviation.isNotEmpty)
                                    item.abbreviation,
                                  if (item.pinyin.isNotEmpty) item.pinyin,
                                ].join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    return autocomplete;
  }

  void _scheduleLockExpiryRefresh(List<dynamic> activeForeignLocks) {
    _lockExpiryTimer?.cancel();
    _lockExpiryTimer = null;
    if (activeForeignLocks.isEmpty) return;
    final earliest = activeForeignLocks
        .map((lock) => lock.expiresAt as DateTime)
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final delay = earliest.difference(DateTime.now());
    _lockExpiryTimer = Timer(
      delay.isNegative
          ? Duration.zero
          : delay + const Duration(milliseconds: 20),
      () {
        if (mounted) setState(() {});
      },
    );
  }
}

class _ScoredOption {
  final DictionaryItem option;
  final int score;

  _ScoredOption(this.option, this.score);
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
