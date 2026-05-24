import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/settings_provider.dart';

/// A text field for callsign input that shows a history overlay when
/// the entered callsign matches past records. Selecting a history item
/// fills all form controllers from that record.
class CallsignHistoryField extends StatefulWidget {
  final TextEditingController callsignController;
  final TextEditingController deviceController;
  final TextEditingController antennaController;
  final TextEditingController qthController;
  final TextEditingController powerController;
  final TextEditingController heightController;
  final String label;
  final String hintText;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool isCompact;

  const CallsignHistoryField({
    super.key,
    required this.callsignController,
    required this.deviceController,
    required this.antennaController,
    required this.qthController,
    required this.powerController,
    required this.heightController,
    required this.label,
    required this.hintText,
    this.textInputAction,
    this.focusNode,
    this.isCompact = false,
  });

  @override
  State<CallsignHistoryField> createState() => _CallsignHistoryFieldState();
}

class _CallsignHistoryFieldState extends State<CallsignHistoryField> {
  List<LogEntry> _history = [];
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _ownFocusNode = FocusNode();
  bool _isSelecting = false;

  FocusNode get _effFocus => widget.focusNode ?? _ownFocusNode;

  @override
  void initState() {
    super.initState();
    _effFocus.addListener(_onFocusChanged);
    widget.callsignController.addListener(_onCallsignChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    widget.callsignController.removeListener(_onCallsignChanged);
    _effFocus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _ownFocusNode.dispose();
    super.dispose();
  }

  void _onCallsignChanged() {
    _loadHistory();
    if (_overlayEntry != null) _hideOverlay();
  }

  void _onFocusChanged() {
    if (_effFocus.hasFocus && _history.isNotEmpty) {
      _showOverlay();
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_effFocus.hasFocus && !_isSelecting) _hideOverlay();
      });
    }
  }

  Future<void> _loadHistory() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.callSignQthLinkEnabled) {
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    final callsign = widget.callsignController.text.trim().toUpperCase();
    if (callsign.length < 2) {
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    final db = DatabaseHelper();
    final rows = await db.getLogsByCallsign(callsign);
    if (mounted) {
      setState(() => _history = rows);
      if (_effFocus.hasFocus && _history.isNotEmpty) {
        _showOverlay();
      }
    }
  }

  void _fillFromRecord(LogEntry log) {
    // Only fill fields that are currently empty
    if (widget.deviceController.text.isEmpty) {
      widget.deviceController.text = log.device;
    }
    if (widget.antennaController.text.isEmpty) {
      widget.antennaController.text = log.antenna;
    }
    if (widget.qthController.text.isEmpty) {
      widget.qthController.text = log.qth;
    }
    if (widget.powerController.text.isEmpty) {
      widget.powerController.text = log.power;
    }
    if (widget.heightController.text.isEmpty) {
      widget.heightController.text = log.height;
    }
    _hideOverlay();
  }

  void _showOverlay() {
    _hideOverlay();
    if (_history.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final historyList = _history;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
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
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(ctx).colorScheme.outline.withAlpha(128)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primaryContainer.withAlpha(128),
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 16, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(historyList.first.callsign.toUpperCase(),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.primary)),
                      const SizedBox(width: 4),
                      Text('的历史记录', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                  Divider(height: 1, color: Theme.of(ctx).colorScheme.outline.withAlpha(77)),
                  Flexible(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: historyList.length,
                      itemBuilder: (_, index) {
                        final log = historyList[index];
                        final parts = <String>[];
                        if (log.qth.isNotEmpty) parts.add(log.qth);
                        if (log.device.isNotEmpty) parts.add(log.device);
                        if (log.antenna.isNotEmpty) parts.add(log.antenna);
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _fillFromRecord(log),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: index < historyList.length - 1
                                    ? Border(bottom: BorderSide(color: Theme.of(ctx).colorScheme.outline.withAlpha(51)))
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(Icons.access_time, size: 14, color: Theme.of(ctx).colorScheme.primary.withAlpha(179)),
                                    const SizedBox(width: 6),
                                    Text(log.time, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                                  ]),
                                  if (parts.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(parts.join(' · '), style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                                  ],
                                ],
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
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
          controller: widget.callsignController,
          focusNode: _effFocus,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.isCompact ? 10 : 14),
          ),
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
