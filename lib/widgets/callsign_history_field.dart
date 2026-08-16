import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/utils/ime_safe_upper_case_formatter.dart';
import 'package:openlogtool/utils/log_time.dart';

typedef CallsignHistoryLoader = Future<List<bridge.LogEntry>> Function(
  String callsign,
  int limit,
);

typedef CallsignHistoryReuseCallback = Future<void> Function(
  bridge.LogEntry record,
);

class CallsignHistoryField extends StatefulWidget {
  final TextEditingController callsignController;
  final TextEditingController deviceController;
  final TextEditingController antennaController;
  final TextEditingController qthController;
  final TextEditingController powerController;
  final TextEditingController heightController;
  final TextEditingController? reportController;
  final TextEditingController? rstRcvdController;
  final TextEditingController? controllerController;
  final String label;
  final String hintText;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool isCompact;
  final bool enabled;
  final bool historyEnabled;
  final String? Function(String?)? validator;
  final CallsignHistoryLoader? historyLoader;
  final bool Function(String field)? canFillField;
  final CallsignHistoryReuseCallback? onReuseRecord;

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
    this.controllerController,
    required this.label,
    required this.hintText,
    this.textInputAction,
    this.focusNode,
    this.isCompact = false,
    this.enabled = true,
    this.historyEnabled = true,
    this.validator,
    this.historyLoader,
    this.canFillField,
    this.onReuseRecord,
  });

  @override
  State<CallsignHistoryField> createState() => _CallsignHistoryFieldState();
}

class _CallsignHistoryFieldState extends State<CallsignHistoryField>
    with WidgetsBindingObserver {
  static const int _historyLimit = 10;

  List<bridge.LogEntry> _history = [];
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final GlobalKey _overlayPanelKey = GlobalKey();
  final FocusNode _ownFocusNode = FocusNode();
  late final FocusOnKeyEventCallback _historyKeyHandler;
  FocusNode? _keyHandlerNode;
  FocusOnKeyEventCallback? _previousKeyHandler;
  Timer? _focusLossTimer;
  bool _isSelecting = false;
  int _historyRequestGeneration = 0;
  int _highlightIndex = -1;
  final ScrollController _listController = ScrollController();
  List<GlobalKey> _historyItemKeys = const [];

  FocusNode get _effFocus => widget.focusNode ?? _ownFocusNode;
  bool get _canUseHistory => widget.enabled && widget.historyEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _historyKeyHandler = _handleKeyEvent;
    _attachKeyHandler(_effFocus);
    _effFocus.addListener(_onFocusChanged);
    widget.callsignController.addListener(_onCallsignChanged);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isKeyPress ||
        !node.hasFocus ||
        _overlayEntry == null ||
        _history.isEmpty ||
        _isSelecting) {
      return _previousKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_highlightIndex >= 0 && _highlightIndex < _history.length) {
        unawaited(_fillFromRecord(_history[_highlightIndex]));
        return KeyEventResult.handled;
      }
      return _previousKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      _hideOverlay();
      return KeyEventResult.handled;
    }
    return _previousKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _attachKeyHandler(FocusNode node) {
    _keyHandlerNode = node;
    _previousKeyHandler = node.onKeyEvent;
    node.onKeyEvent = _historyKeyHandler;
  }

  void _detachKeyHandler() {
    final node = _keyHandlerNode;
    if (node != null && identical(node.onKeyEvent, _historyKeyHandler)) {
      node.onKeyEvent = _previousKeyHandler;
    }
    _keyHandlerNode = null;
    _previousKeyHandler = null;
  }

  @override
  void didUpdateWidget(CallsignHistoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFocus = oldWidget.focusNode ?? _ownFocusNode;
    if (oldFocus != _effFocus) {
      _detachKeyHandler();
      oldFocus.removeListener(_onFocusChanged);
      _attachKeyHandler(_effFocus);
      _effFocus.addListener(_onFocusChanged);
    }
    if (oldWidget.callsignController != widget.callsignController) {
      oldWidget.callsignController.removeListener(_onCallsignChanged);
      widget.callsignController.addListener(_onCallsignChanged);
      _invalidateHistory();
    }
    final wasUsable = oldWidget.enabled && oldWidget.historyEnabled;
    if (wasUsable && !_canUseHistory) {
      _invalidateHistory();
    } else if (!wasUsable && _canUseHistory) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusLossTimer?.cancel();
    _detachKeyHandler();
    _listController.dispose();
    _hideOverlay();
    widget.callsignController.removeListener(_onCallsignChanged);
    _effFocus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _ownFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (_overlayEntry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlayEntry?.markNeedsBuild();
    });
  }

  void _moveHighlight(int delta) {
    if (_history.isEmpty) return;
    final next = (_highlightIndex < 0 ? 0 : _highlightIndex + delta)
        .clamp(0, _history.length - 1);
    if (next == _highlightIndex) return;
    _highlightIndex = next;
    _overlayEntry?.markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = next < _historyItemKeys.length
          ? _historyItemKeys[next].currentContext
          : null;
      if (itemContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            itemContext,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
        return;
      }
      if (!_listController.hasClients) return;
      const itemExtent = 58.0;
      final position = _listController.position;
      final itemTop = next * itemExtent;
      final itemBottom = itemTop + itemExtent;
      var target = position.pixels;
      if (itemTop < position.pixels) {
        target = itemTop;
      } else if (itemBottom > position.pixels + position.viewportDimension) {
        target = itemBottom - position.viewportDimension;
      }
      target = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return;
      _listController.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _onCallsignChanged() {
    if (!_canUseHistory) {
      _invalidateHistory();
      return;
    }
    if (ImeSafeUpperCaseTextFormatter.hasActiveComposition(
      widget.callsignController.value,
    )) {
      _invalidateHistory();
      return;
    }
    _loadHistory();
    if (_overlayEntry != null) _hideOverlay();
  }

  void _onFocusChanged() {
    _focusLossTimer?.cancel();
    _focusLossTimer = null;
    if (!_canUseHistory) {
      _hideOverlay();
      return;
    }
    if (ImeSafeUpperCaseTextFormatter.hasActiveComposition(
      widget.callsignController.value,
    )) {
      _invalidateHistory();
      return;
    }
    final callsign = widget.callsignController.text.trim().toUpperCase();
    if (callsign.length < 2) {
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    if (_effFocus.hasFocus &&
        _history.isNotEmpty &&
        _history.first.callsign.trim().toUpperCase() == callsign) {
      _showOverlay();
    } else if (!_effFocus.hasFocus) {
      _focusLossTimer = Timer(const Duration(milliseconds: 300), () {
        _focusLossTimer = null;
        if (!mounted) return;
        if (!_effFocus.hasFocus && !_isSelecting) _hideOverlay();
      });
    }
  }

  Future<void> _loadHistory() async {
    final requestGeneration = ++_historyRequestGeneration;
    if (!_canUseHistory) return;
    if (ImeSafeUpperCaseTextFormatter.hasActiveComposition(
      widget.callsignController.value,
    )) {
      _invalidateHistory();
      return;
    }
    final callsign = widget.callsignController.text.trim().toUpperCase();
    if (callsign.length < 2) {
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    try {
      final loader = widget.historyLoader ?? _loadHistoryFromDatabase;
      final rows = await loader(callsign, _historyLimit);
      if (!mounted || !_canUseHistory) return;
      if (requestGeneration != _historyRequestGeneration) return;
      if (ImeSafeUpperCaseTextFormatter.hasActiveComposition(
        widget.callsignController.value,
      )) {
        _invalidateHistory();
        return;
      }
      final current = widget.callsignController.text.trim().toUpperCase();
      if (current != callsign) {
        // Controller listener already started the request for the latest text.
        return;
      }
      setState(() => _history = rows);
      if (_effFocus.hasFocus &&
          _history.isNotEmpty &&
          _history.first.callsign.trim().toUpperCase() == current &&
          _overlayEntry == null) {
        _showOverlay();
      } else if (_history.isEmpty) {
        _hideOverlay();
      }
    } catch (_) {}
  }

  Future<List<bridge.LogEntry>> _loadHistoryFromDatabase(
    String callsign,
    int limit,
  ) =>
      RustApi.getRecentByCallsign(callsign: callsign, limit: limit);

  void _invalidateHistory() {
    _historyRequestGeneration += 1;
    _history = const [];
    _hideOverlay();
  }

  bool _canFill(String field) => widget.canFillField?.call(field) ?? true;

  Future<void> _fillFromRecord(bridge.LogEntry log) async {
    _isSelecting = true;
    _hideOverlay();
    try {
      final onReuseRecord = widget.onReuseRecord;
      if (onReuseRecord != null) {
        await onReuseRecord(log);
        return;
      }

      _fillControllersFromRecord(log);
    } finally {
      _isSelecting = false;
    }
  }

  void _fillControllersFromRecord(bridge.LogEntry log) {
    if (_canFill('device') && (log.device?.isNotEmpty ?? false)) {
      widget.deviceController.text = log.device!;
    }
    if (_canFill('antenna') && (log.antenna?.isNotEmpty ?? false)) {
      widget.antennaController.text = log.antenna!;
    }
    if (_canFill('qth') && (log.qth?.isNotEmpty ?? false)) {
      widget.qthController.text = log.qth!;
    }
    if (_canFill('power') && (log.power?.isNotEmpty ?? false)) {
      widget.powerController.text = log.power!;
    }
    if (_canFill('height') && (log.height?.isNotEmpty ?? false)) {
      widget.heightController.text = log.height!;
    }
  }

  void _showOverlay() {
    _hideOverlay();
    if (!_canUseHistory || _history.isEmpty) return;
    _highlightIndex = 0;
    final overlay = Overlay.of(context);
    final list = List<bridge.LogEntry>.unmodifiable(_history);
    _historyItemKeys = List<GlobalKey>.generate(
      list.length,
      (index) => GlobalKey(debugLabel: 'callsign-history-item-$index'),
      growable: false,
    );

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final overlayObject = overlay.context.findRenderObject();
        final fieldObject = context.findRenderObject();
        if (overlayObject is! RenderBox ||
            fieldObject is! RenderBox ||
            !overlayObject.attached ||
            !fieldObject.attached) {
          return const SizedBox.shrink();
        }
        final overlaySize = overlayObject.size;
        final fieldSize = fieldObject.size;
        final fieldOrigin = fieldObject.localToGlobal(
          Offset.zero,
          ancestor: overlayObject,
        );
        const screenMargin = 8.0;
        const anchorGap = 4.0;
        final mediaQuery = MediaQuery.of(ctx);
        final view = View.of(ctx);
        final rawBottomInset = view.viewInsets.bottom / view.devicePixelRatio;
        final bottomInset = math.max(
          mediaQuery.viewInsets.bottom,
          rawBottomInset,
        );
        final availableWidth = math.max(
          0.0,
          overlaySize.width - screenMargin * 2,
        );
        final panelWidth = math.min(320.0, availableWidth);
        final maxLeft = math.max(
          screenMargin,
          overlaySize.width - screenMargin - panelWidth,
        );
        final panelLeft =
            fieldOrigin.dx.clamp(screenMargin, maxLeft).toDouble();
        final desiredHeight = math.min(260.0, 42.0 + list.length * 58.0);
        final visibleTop = mediaQuery.padding.top + screenMargin;
        final visibleBottom = overlaySize.height -
            bottomInset -
            mediaQuery.padding.bottom -
            screenMargin;
        final belowSpace = math.max(
          0.0,
          visibleBottom - (fieldOrigin.dy + fieldSize.height + anchorGap),
        );
        final aboveSpace = math.max(
          0.0,
          fieldOrigin.dy - anchorGap - visibleTop,
        );
        final openBelow = belowSpace >= math.min(desiredHeight, 120.0) ||
            belowSpace >= aboveSpace;
        final availableHeight = openBelow ? belowSpace : aboveSpace;
        final panelHeight = math.min(desiredHeight, availableHeight);
        final followerOffset = Offset(
          panelLeft - fieldOrigin.dx,
          openBelow ? fieldSize.height + anchorGap : -panelHeight - anchorGap,
        );
        return Positioned(
          width: panelWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: followerOffset,
            child: TextFieldTapRegion(
              child: Material(
                key: const Key('callsign-history-overlay'),
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                surfaceTintColor: Colors.transparent,
                child: Container(
                  key: _overlayPanelKey,
                  constraints: BoxConstraints(maxHeight: panelHeight),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Theme.of(ctx).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .outlineVariant)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.auto_fix_high,
                                size: 14,
                                color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                context.l10n.reuseDatabaseInformation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Scrollbar(
                          controller: _listController,
                          child: ListView.builder(
                            key: const Key('callsign-history-list'),
                            controller: _listController,
                            primary: false,
                            physics: const ClampingScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final log = list[i];
                              final details = [
                                if (log.qth != null && log.qth!.isNotEmpty)
                                  log.qth,
                                if (log.device != null &&
                                    log.device!.isNotEmpty)
                                  log.device,
                                if (log.antenna != null &&
                                    log.antenna!.isNotEmpty)
                                  log.antenna,
                              ].join(' · ');
                              final selected = i == _highlightIndex;
                              return Semantics(
                                key: _historyItemKeys[i],
                                selected: selected,
                                button: true,
                                child: InkWell(
                                  onTap: () => unawaited(_fillFromRecord(log)),
                                  onHover: (hovered) {
                                    if (hovered && _highlightIndex != i) {
                                      _highlightIndex = i;
                                      _overlayEntry?.markNeedsBuild();
                                    }
                                  },
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 58),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? Theme.of(ctx)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.14)
                                          : null,
                                      border: i < list.length - 1
                                          ? Border(
                                              bottom: BorderSide(
                                                color: Theme.of(ctx)
                                                    .colorScheme
                                                    .outlineVariant
                                                    .withAlpha(80),
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.history,
                                          size: 14,
                                          color:
                                              Theme.of(ctx).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatTime(log.time),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(ctx)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                              if (details.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child: Text(
                                                    details,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Theme.of(ctx)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    _historyItemKeys = const [];
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
        enabled: widget.enabled,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
              horizontal: 12, vertical: widget.isCompact ? 10 : 14),
          suffixIcon: _canUseHistory
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.search,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
        textInputAction: widget.textInputAction ?? TextInputAction.next,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: const [ImeSafeUpperCaseTextFormatter()],
        onTapOutside: (event) {
          final overlayContext = _overlayPanelKey.currentContext;
          if (overlayContext != null) {
            final renderObject = overlayContext.findRenderObject();
            if (renderObject is RenderBox && renderObject.attached) {
              final local = renderObject.globalToLocal(event.position);
              if (local.dx >= 0 &&
                  local.dy >= 0 &&
                  local.dx <= renderObject.size.width &&
                  local.dy <= renderObject.size.height) {
                return;
              }
            }
          }
          _effFocus.unfocus();
        },
      ),
    );
  }
}

String _formatTime(String time) {
  return formatLogTimeForDisplay(time, includeDate: true);
}
