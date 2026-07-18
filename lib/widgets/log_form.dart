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
import 'package:openlogtool/utils/ime_safe_upper_case_formatter.dart';
import 'package:openlogtool/utils/log_time.dart';
import 'package:openlogtool/widgets/callsign_history_field.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;

/// 日志表单组件
/// 用于添加和编辑点名记录
class LogForm extends StatefulWidget {
  const LogForm({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  State<LogForm> createState() => _LogFormState();
}

class _LogFormState extends State<LogForm> with AutomaticKeepAliveClientMixin {
  static const _upperCaseDraftFields = {'controller', 'callsign'};

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
  bool _historyReuseInProgress = false;
  bool _submissionInProgress = false;
  String? _lastSharedDraftSignature;
  String? _lastSharedDraftId;
  final Set<String> _deferredSharedDraftFields = <String>{};

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
    final fields = collaboration.liveDraftDisplayFields;
    if (snapshot == null || fields == null) {
      _lastSharedDraftId = null;
      _lastSharedDraftSignature = null;
      _deferredSharedDraftFields.clear();
      return;
    }
    final signature = '${snapshot.draft.draftId}:${snapshot.draft.version}:'
        '${fields.toJson()}';
    if (_lastSharedDraftSignature == signature &&
        _deferredSharedDraftFields.isEmpty) {
      return;
    }
    final draftChanged = _lastSharedDraftId != snapshot.draft.draftId;
    if (draftChanged) _deferredSharedDraftFields.clear();
    _lastSharedDraftId = snapshot.draft.draftId;
    _lastSharedDraftSignature = signature;
    _applyingSharedDraft = true;
    try {
      for (final entry in _draftControllers.entries) {
        final rawValue = fields[entry.key];
        final value =
            entry.key == 'time' ? _displayLiveDraftTime(rawValue) : rawValue;
        if (_hasActiveUpperCaseComposition(entry.key)) {
          if (entry.value.text != value) {
            _deferredSharedDraftFields.add(entry.key);
          } else {
            _deferredSharedDraftFields.remove(entry.key);
          }
          continue;
        }
        if (!draftChanged && _focusedDraftFields.contains(entry.key)) {
          if (entry.value.text != value) {
            _deferredSharedDraftFields.add(entry.key);
          } else {
            _deferredSharedDraftFields.remove(entry.key);
          }
          continue;
        }
        _deferredSharedDraftFields.remove(entry.key);
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
    if (_hasActiveUpperCaseComposition(field)) {
      _draftDebounce.remove(field)?.cancel();
      return;
    }
    final collaboration = context.read<CollaborationProvider>();
    if (field == 'time') collaboration.cancelAutomaticLiveDraftTime();
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
    _commitUpperCaseDraftField(field);
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
    if (mounted && _deferredSharedDraftFields.contains(field)) {
      _syncSharedDraft(collaboration);
    }
  }

  bool _hasActiveUpperCaseComposition(String field) {
    final controller = _draftControllers[field];
    return _upperCaseDraftFields.contains(field) &&
        controller != null &&
        ImeSafeUpperCaseTextFormatter.hasActiveComposition(controller.value);
  }

  void _commitUpperCaseDraftField(String field) {
    if (!_upperCaseDraftFields.contains(field)) return;
    final controller = _draftControllers[field];
    if (controller == null) return;
    final committed = ImeSafeUpperCaseTextFormatter.commit(controller.value);
    if (committed != controller.value) controller.value = committed;
  }

  void _commitUpperCaseIdentifiers() {
    for (final field in _upperCaseDraftFields) {
      _commitUpperCaseDraftField(field);
    }
  }

  String _displayLiveDraftTime(String value) {
    return formatLogTimeForDisplay(value);
  }

  void _unfocusDraftFields() {
    FocusManager.instance.primaryFocus?.unfocus();
    for (final focusNode in _draftFocusNodes.values) {
      if (focusNode.hasFocus) focusNode.unfocus();
    }
  }

  Future<void> _reuseHistoryRecord(bridge.LogEntry record) async {
    final values = <String, String>{
      if (record.device?.isNotEmpty ?? false) 'device': record.device!,
      if (record.antenna?.isNotEmpty ?? false) 'antenna': record.antenna!,
      if (record.qth?.isNotEmpty ?? false) 'qth': record.qth!,
      if (record.power?.isNotEmpty ?? false) 'power': record.power!,
      if (record.height?.isNotEmpty ?? false) 'height': record.height!,
    };
    if (values.isEmpty || !mounted) return;

    final collaboration = context.read<CollaborationProvider>();
    if (collaboration.liveDraftSnapshot != null) {
      for (final field in values.keys) {
        final holder = collaboration.lockForField(field);
        if (holder != null &&
            holder.expiresAt.isAfter(DateTime.now()) &&
            collaboration.fieldLockedByAnotherUser(field)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n.fieldLockedBy(holder.username))),
          );
          return;
        }
      }

      for (final field in values.keys) {
        _draftDebounce.remove(field)?.cancel();
      }
      _unfocusDraftFields();
      setState(() => _historyReuseInProgress = true);
      try {
        await collaboration.updateLiveDraftFieldsAtomically(values);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n.operationFailed(error.toString()))),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _historyReuseInProgress = false);
      }
      if (!mounted) return;
      // The provider adopts the canonical multi-field response and notifies
      // this form. Let _syncSharedDraft drive the controllers so a newer edit
      // made while the request was in flight is never overwritten here.
      return;
    }

    _applyingSharedDraft = true;
    try {
      for (final entry in values.entries) {
        final controller = _draftControllers[entry.key];
        if (controller == null || controller.text == entry.value) continue;
        controller.value = TextEditingValue(
          text: entry.value,
          selection: TextSelection.collapsed(offset: entry.value.length),
        );
      }
    } finally {
      _applyingSharedDraft = false;
    }
  }

  Future<void> _submitForm() async {
    if (_submissionInProgress) return;
    _commitUpperCaseIdentifiers();
    final collaboration = context.read<CollaborationProvider>();
    if (widget.readOnly ||
        (collaboration.binding != null &&
            collaboration.liveDraftSnapshot != null &&
            !collaboration.canEditLiveDraft)) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submissionInProgress = true);
    try {
      await _submitValidatedForm(collaboration);
    } catch (error, stackTrace) {
      debugPrint('[LogForm] submit failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.operationFailed('$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _submissionInProgress = false);
    }
  }

  Future<void> _submitValidatedForm(
    CollaborationProvider collaboration,
  ) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final sessionProvider =
        Provider.of<SessionProvider>(context, listen: false);
    final dictionaryProvider =
        Provider.of<DictionaryProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final enteredTime = _timeController.text.trim();
    final usesAutomaticTime = enteredTime.isEmpty;
    final submittedTime = resolveLogTimeForSubmission(enteredTime);
    final submittedFields = <String, String>{
      for (final entry in _draftControllers.entries)
        entry.key: entry.key == 'time' ? submittedTime : entry.value.text,
    };

    final normalizedCallsign =
        submittedFields['callsign']!.trim().toUpperCase();
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

    if (submittedFields['device']!.isNotEmpty) {
      await dictionaryProvider.addDevice(submittedFields['device']!);
    }
    if (submittedFields['antenna']!.isNotEmpty) {
      await dictionaryProvider.addAntenna(submittedFields['antenna']!);
    }
    if (submittedFields['callsign']!.isNotEmpty) {
      await dictionaryProvider.addCallsign(submittedFields['callsign']!);
    }
    if (submittedFields['qth']!.isNotEmpty) {
      await dictionaryProvider.addQth(submittedFields['qth']!);
    }
    if (!mounted) return;

    if (collaboration.binding != null &&
        collaboration.liveDraftSnapshot != null) {
      if (usesAutomaticTime) {
        collaboration.beginAutomaticLiveDraftTime(submittedTime);
      } else {
        collaboration.cancelAutomaticLiveDraftTime();
      }
      for (final timer in _draftDebounce.values) {
        timer.cancel();
      }
      _draftDebounce.clear();
      for (final entry in submittedFields.entries) {
        try {
          await collaboration.updateLiveDraftField(
            entry.key,
            entry.value,
          );
          if (usesAutomaticTime && entry.key == 'time') {
            collaboration.confirmAutomaticLiveDraftTime();
          }
        } catch (_) {
          // commitCurrentLiveDraft retries retained dirty values and decides
          // whether a network failure should enter the offline review queue.
        }
      }
      final disposition = await collaboration.commitCurrentLiveDraft();
      if (usesAutomaticTime) {
        collaboration.completeAutomaticLiveDraftTime(disposition);
      }
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
      time: submittedTime,
      controller: submittedFields['controller']!,
      callsign: submittedFields['callsign']!,
      report: submittedFields['rstSent']!,
      rstRcvd: submittedFields['rstRcvd']!,
      qth: submittedFields['qth']!,
      device: submittedFields['device']!,
      power: submittedFields['power']!,
      antenna: submittedFields['antenna']!,
      height: submittedFields['height']!,
    );
    log.remarks = submittedFields['remarks']!;

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
    final canSubmit = !readOnly &&
        firstForeignLock == null &&
        !_historyReuseInProgress &&
        !_submissionInProgress;

    bool fieldEnabled(String field) => !readOnly && !isActiveForeignLock(field);

    String fieldLabel(String field, String fallback) {
      final lock = collaboration.lockForField(field);
      if (lock == null || !isActiveForeignLock(field)) {
        return fallback;
      }
      return '$fallback · ${context.l10n.fieldLockedBy(lock.username)}';
    }

    final content = LayoutBuilder(
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

        return AbsorbPointer(
          key: const Key('history-reuse-guard'),
          absorbing: _historyReuseInProgress,
          child: Form(
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
                        label: fieldLabel(
                          'controller',
                          '${context.l10n.fieldControllerCallsign} *',
                        ),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldControllerCallsign,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return context.l10n.fieldRequired;
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
                        controllerController: _controllerController,
                        label: fieldLabel(
                          'callsign',
                          context.l10n.fieldCallsign,
                        ),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldCallsign,
                        ),
                        focusNode: _callsignFocusNode,
                        isCompact: isNarrow,
                        textInputAction: TextInputAction.next,
                        enabled: fieldEnabled('callsign'),
                        historyEnabled: settingsProvider.callSignQthLinkEnabled,
                        onReuseRecord: _reuseHistoryRecord,
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
                        label: fieldLabel('device', context.l10n.fieldDevice),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldDevice,
                        ),
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
                        label: fieldLabel('antenna', context.l10n.fieldAntenna),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldAntenna,
                        ),
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
                        label: fieldLabel('power', context.l10n.fieldPower),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldPower,
                        ),
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
                        label: fieldLabel('qth', context.l10n.fieldQth),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldQth,
                        ),
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
                        label: fieldLabel('height', context.l10n.fieldHeight),
                        hintText: context.l10n.inputFieldHint(
                          context.l10n.fieldHeight,
                        ),
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
                        key: const Key('log-time-field'),
                        controller: _timeController,
                        label: fieldLabel('time', context.l10n.fieldTime),
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
                        label: fieldLabel('rstSent', context.l10n.fieldRstSent),
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
                        label: fieldLabel('rstRcvd', context.l10n.fieldRstRcvd),
                        hintText: '59',
                        upperCase: false,
                        isCompact: isNarrow,
                        textInputAction: TextInputAction.next,
                        focusNode: _draftFocusNodes['rstRcvd'],
                        enabled: fieldEnabled('rstRcvd'),
                      ),
                    ),
                    SizedBox(
                      width: calculatedFieldWidth,
                      child: _buildMaterialTextField(
                        controller: _remarksController,
                        label: fieldLabel('remarks', context.l10n.fieldRemarks),
                        hintText: context.l10n.optionalFieldHint(
                          context.l10n.fieldRemarks,
                        ),
                        upperCase: false,
                        isCompact: isNarrow,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _unfocusDraftFields(),
                        focusNode: _draftFocusNodes['remarks'],
                        enabled: fieldEnabled('remarks'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (sharedDraft &&
                    collaboration.ownedLiveDraftLocks.isNotEmpty) ...[
                  OutlinedButton.icon(
                    key: const Key('finish-draft-editing'),
                    onPressed:
                        _historyReuseInProgress ? null : _unfocusDraftFields,
                    icon: const Icon(Icons.keyboard_hide_outlined),
                    label: Text(context.l10n.finishEditing),
                  ),
                  const SizedBox(height: 8),
                ],

                // 操作按钮 - 占满宽度
                Tooltip(
                  message: 'Ctrl/⌘ + Enter',
                  child: SizedBox(
                    height: isNarrow ? 44 : 48,
                    child: FilledButton.icon(
                      key: const Key('save-log-record'),
                      onPressed: canSubmit ? _submitForm : null,
                      icon: Icon(
                        _historyReuseInProgress
                            ? Icons.auto_fix_high
                            : readOnly || firstForeignLock != null
                                ? Icons.lock_outline
                                : Icons.add,
                      ),
                      label: Text(
                        _historyReuseInProgress
                            ? context.l10n.reuseDatabaseInformation
                            : readOnly
                                ? context.l10n.sharedDraftReadOnly
                                : firstForeignLock != null
                                    ? context.l10n.fieldLockedBy(
                                        firstForeignLock.username,
                                      )
                                    : context.l10n.saveRecord,
                      ),
                      style: ElevatedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(vertical: isNarrow ? 10 : 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (canSubmit) unawaited(_submitForm());
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (canSubmit) unawaited(_submitForm());
        },
      },
      child: content,
    );
  }

  Widget _buildMaterialTextField({
    Key? key,
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
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: error,
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
      inputFormatters:
          upperCase ? const [ImeSafeUpperCaseTextFormatter()] : const [],
      onTapOutside: (_) => focusNode?.unfocus(),
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
    final List<TextInputFormatter> inputFormatters = upperCase
        ? const [ImeSafeUpperCaseTextFormatter()]
        : const <TextInputFormatter>[];

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
          onTapOutside: (_) => fieldFocusNode.unfocus(),
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
