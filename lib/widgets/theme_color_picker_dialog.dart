import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/hsv_color_painter.dart';

class ThemeColorPreset {
  const ThemeColorPreset(this.color, this.label);

  final Color color;
  final String Function(AppLocalizations l10n) label;
}

/// A single color-selection surface for both presets and custom colors.
///
/// Presets update the same HSV/HEX controls as manual selection and nothing is
/// persisted until the user presses Apply. This avoids the old nested dialogs,
/// whose preset lists and confirmation behavior differed.
class ThemeColorPickerDialog extends StatefulWidget {
  const ThemeColorPickerDialog({
    super.key,
    required this.initialColor,
  });

  final Color initialColor;

  @override
  State<ThemeColorPickerDialog> createState() => _ThemeColorPickerDialogState();
}

class _ThemeColorPickerDialogState extends State<ThemeColorPickerDialog> {
  static const _hueGradient = LinearGradient(
    colors: [
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ],
  );

  late HSVColor _hsv;
  late final TextEditingController _hexController;
  late final ScrollController _scrollController;

  Color get _color => _hsv.toColor().withAlpha(255);

  List<ThemeColorPreset> get _presets => [
        ThemeColorPreset(
          const Color(0xFF2196F3),
          (l10n) => l10n.themeColorBlue,
        ),
        ThemeColorPreset(
          const Color(0xFF4CAF50),
          (l10n) => l10n.themeColorGreen,
        ),
        ThemeColorPreset(
          const Color(0xFFF44336),
          (l10n) => l10n.themeColorRed,
        ),
        ThemeColorPreset(
          const Color(0xFFFF9800),
          (l10n) => l10n.themeColorOrange,
        ),
        ThemeColorPreset(
          const Color(0xFF9C27B0),
          (l10n) => l10n.themeColorPurple,
        ),
        ThemeColorPreset(
          const Color(0xFFFF93B7),
          (l10n) => l10n.themeColorPink,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor.withAlpha(255));
    _hexController = TextEditingController(text: _hexFor(_color));
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _hexController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color.withAlpha(255)));
    _syncHex();
  }

  void _setHsv(HSVColor color) {
    setState(() => _hsv = color.withAlpha(1));
    _syncHex();
  }

  void _syncHex() {
    final value = _hexFor(_color);
    if (_hexController.text == value) return;
    _hexController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _updateFromHex(String value) {
    final normalized = value.replaceFirst('#', '');
    if (normalized.length != 6) return;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return;
    setState(() {
      _hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
    });
  }

  void _updateSaturationAndValue(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = 1 - (position.dy / size.height).clamp(0.0, 1.0);
    _setHsv(_hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final presets = _presets;
    return AlertDialog(
      key: const Key('theme-color-picker-dialog'),
      title: Text(l10n.themeColorPickerTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              key: const Key('theme-color-content-scroll'),
              controller: _scrollController,
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.themeColorPresets,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 3,
                    runSpacing: 4,
                    children: [
                      for (final preset in presets)
                        _PresetButton(
                          key: ValueKey(
                              'theme-color-${preset.color.toARGB32()}'),
                          color: preset.color,
                          label: preset.label(l10n),
                          selected:
                              preset.color.toARGB32() == _color.toARGB32(),
                          onPressed: () => _setColor(preset.color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(
                    l10n.themeColorCustom,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  AspectRatio(
                    aspectRatio: 2.15,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Builder(
                          builder: (colorAreaContext) {
                            void update(DragUpdateDetails details) {
                              final renderBox =
                                  colorAreaContext.findRenderObject();
                              if (renderBox is! RenderBox ||
                                  !renderBox.hasSize) {
                                return;
                              }
                              _updateSaturationAndValue(
                                details.localPosition,
                                renderBox.size,
                              );
                            }

                            return GestureDetector(
                              key: const Key('theme-color-sv-area'),
                              onPanStart: (details) {
                                final renderBox =
                                    colorAreaContext.findRenderObject();
                                if (renderBox is! RenderBox ||
                                    !renderBox.hasSize) {
                                  return;
                                }
                                _updateSaturationAndValue(
                                  details.localPosition,
                                  renderBox.size,
                                );
                              },
                              onPanUpdate: update,
                              child: CustomPaint(
                                painter: HsvSaturationValuePainter(
                                  _hsv.hue,
                                  _hsv.saturation,
                                  _hsv.value,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        key: const Key('theme-color-preview'),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.outline),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const Key('theme-color-hex-field'),
                          controller: _hexController,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(7),
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[#0-9a-fA-F]'),
                            ),
                          ],
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: l10n.themeColorHex,
                            prefixText: _hexController.text.startsWith('#')
                                ? null
                                : '#',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontFamily: 'monospace'),
                          onChanged: _updateFromHex,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(l10n.themeColorHue),
                      ),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 16,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: _hueGradient,
                              ),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 16,
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                key: const Key('theme-color-hue-slider'),
                                value: _hsv.hue,
                                min: 0,
                                max: 360,
                                onChanged: (value) =>
                                    _setHsv(_hsv.withHue(value)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('apply-theme-color'),
          onPressed: () => Navigator.pop(context, _color),
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, color: _foregroundFor(color), size: 18)
                    : null,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hexFor(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color _foregroundFor(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
