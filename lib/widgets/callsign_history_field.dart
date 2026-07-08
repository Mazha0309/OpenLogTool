import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;

class CallsignHistoryField extends StatefulWidget {
  final TextEditingController callsignController;
  final TextEditingController deviceController;
  final TextEditingController antennaController;
  final TextEditingController qthController;
  final TextEditingController powerController;
  final TextEditingController heightController;
  final TextEditingController? reportController;
  final TextEditingController? rstRcvdController;
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
    this.reportController,
    this.rstRcvdController,
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
  List<bridge.LogEntry> _history = [];
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _ownFocusNode = FocusNode();
  final bool _isSelecting = false;

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
    final callsign = widget.callsignController.text.trim().toUpperCase();
    if (callsign.length < 2) {
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    try {
      final rows = await RustApi.getRecentByCallsign(callsign: callsign, limit: 3);
      if (mounted) {
        setState(() => _history = rows);
        if (_effFocus.hasFocus && _history.isNotEmpty && _overlayEntry == null) {
          _showOverlay();
        }
      }
    } catch (_) {}
  }

  void _fillFromRecord(bridge.LogEntry log) {
    if (widget.deviceController.text.isEmpty) widget.deviceController.text = log.device ?? '';
    if (widget.antennaController.text.isEmpty) widget.antennaController.text = log.antenna ?? '';
    if (widget.qthController.text.isEmpty) widget.qthController.text = log.qth ?? '';
    if (widget.powerController.text.isEmpty) widget.powerController.text = log.power ?? '';
    if (widget.heightController.text.isEmpty) widget.heightController.text = log.height ?? '';
    if (widget.reportController != null && widget.reportController!.text.isEmpty) {
      widget.reportController!.text = log.rstSent ?? '';
    }
    if (widget.rstRcvdController != null && widget.rstRcvdController!.text.isEmpty) {
      widget.rstRcvdController!.text = log.rstRcvd ?? '';
    }
    _hideOverlay();
  }

  void _showOverlay() {
    _hideOverlay();
    if (_history.isEmpty) return;

    final overlay = Overlay.of(context);
    final size = (context.findRenderObject() as RenderBox).size;
    final list = _history;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            surfaceTintColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant)),
                    ),
                    child: Text('最近记录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final log = list[i];
                        final details = [
                          if (log.qth != null && log.qth!.isNotEmpty) log.qth,
                          if (log.device != null && log.device!.isNotEmpty) log.device,
                          if (log.antenna != null && log.antenna!.isNotEmpty) log.antenna,
                        ].join(' · ');
                        return InkWell(
                          onTap: () => _fillFromRecord(log),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: i < list.length - 1
                                  ? Border(bottom: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant.withAlpha(80)))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.history, size: 14, color: Theme.of(ctx).colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.time.length >= 16 ? log.time.substring(11, 16) : log.time,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.primary),
                                      ),
                                      if (details.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(details, style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 16, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                              ],
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
    try { entry.remove(); } catch (_) {}
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
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.search, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
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
