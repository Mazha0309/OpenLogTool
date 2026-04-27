import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/providers/settings_provider.dart';

class QthFieldWithHistory extends StatefulWidget {
  final TextEditingController controller;
  final TextEditingController callsignController;
  final List<DictionaryItem> dictionaryOptions;
  final String label;
  final String hintText;
  final TextInputAction? textInputAction;
  final bool isCompact;

  const QthFieldWithHistory({
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
  State<QthFieldWithHistory> createState() => QthFieldWithHistoryState();
}

class QthFieldWithHistoryState extends State<QthFieldWithHistory> {
  List<Map<String, dynamic>> _history = [];
  String _lastCallsign = '';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _focusNode = FocusNode();
  bool _isSelectingHistory = false;

  @override
  void initState() {
    super.initState();
    _lastCallsign = widget.callsignController.text;
    widget.callsignController.addListener(_onCallsignChanged);
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
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
    _lastCallsign = widget.callsignController.text;
    _loadHistory();
    if (_overlayEntry != null) _hideOverlay();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (widget.controller.text.isEmpty &&
          _history.isNotEmpty &&
          _overlayEntry == null) {
        _showOverlay();
      }
    } else {
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
      if (mounted) setState(() => _history = []);
      _hideOverlay();
      return;
    }
    final db = DatabaseHelper();
    final history = await db.getCallsignQthHistory(_lastCallsign);
    if (mounted) {
      setState(() => _history = history);
      if (_focusNode.hasFocus &&
          widget.controller.text.isEmpty &&
          _history.isNotEmpty &&
          _overlayEntry == null) {
        _showOverlay();
      }
    }
  }

  void refresh() => _loadHistory();

  void _showOverlay() {
    _hideOverlay();
    if (_history.isEmpty) return;
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final _historyList = _history;

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
                    color: Theme.of(context).colorScheme.outline.withAlpha(128)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(128),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(_lastCallsign.toUpperCase(),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 4),
                      Text('的历史QTH',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ]),
                  ),
                  Divider(
                      height: 1,
                      color:
                          Theme.of(context).colorScheme.outline.withAlpha(77)),
                  Flexible(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _historyList.length,
                      itemBuilder: (context, index) {
                        final item = _historyList[index];
                        final qth = item['qth'] as String;
                        final recordedAt = item['recorded_at'] as String?;
                        String subtitle = '';
                        if (recordedAt != null) {
                          final dt = DateTime.parse(recordedAt);
                          subtitle =
                              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                        }
                        return Material(
                          color: Colors.transparent,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (_) => _isSelectingHistory = true,
                            onPointerUp: (_) {
                              widget.controller.text = qth;
                              _isSelectingHistory = false;
                              _hideOverlay();
                            },
                            child: InkWell(
                              onTap: () {
                                widget.controller.text = qth;
                                _isSelectingHistory = false;
                                _hideOverlay();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: index < _historyList.length - 1
                                      ? Border(
                                          bottom: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withAlpha(51)))
                                      : null,
                                ),
                                child: Row(children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(179)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(qth,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500)),
                                        if (subtitle.isNotEmpty)
                                          Text(subtitle,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ]),
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
        if (_overlayEntry != null) _hideOverlay();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Autocomplete<DictionaryItem>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<DictionaryItem>.empty();
            }
            return widget.dictionaryOptions
                .where((option) => option.matches(textEditingValue.text));
          },
          onSelected: (DictionaryItem selection) {
            widget.controller.text = selection.raw;
            _hideOverlay();
          },
          fieldViewBuilder: (context, fieldController, fieldFocusNode,
              onFieldSubmitted) {
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
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: widget.isCompact ? 10 : 14),
              ),
              onTap: () {
                if (fieldController.text.isEmpty &&
                    _history.isNotEmpty &&
                    _overlayEntry == null) {
                  _showOverlay();
                }
              },
              onChanged: (value) {
                widget.controller.text = value;
                if (_overlayEntry != null) _hideOverlay();
              },
              textInputAction: widget.textInputAction ?? TextInputAction.next,
            );
          },
          optionsViewBuilder:
              (context, AutocompleteOnSelected<DictionaryItem> onSelected,
                  Iterable<DictionaryItem> options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 200, maxWidth: 300),
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
