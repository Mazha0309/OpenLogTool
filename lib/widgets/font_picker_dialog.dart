import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/theme/app_theme.dart';

class FontPickerResult {
  const FontPickerResult(this.fontFamily);

  final String? fontFamily;
}

/// Selects a font without rendering every list row in a different family.
///
/// Font discovery can return hundreds of families. Asking the text engine to
/// resolve a different family for every scrolling row causes visible stalls on
/// desktop. The list therefore stays in the app font and only the single
/// preview surface renders the pending family.
class FontPickerDialog extends StatefulWidget {
  const FontPickerDialog({
    super.key,
    required this.availableFonts,
    required this.currentFont,
  });

  final List<String> availableFonts;
  final String? currentFont;

  @override
  State<FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<FontPickerDialog> {
  late final TextEditingController _searchController;
  late final List<_FontOption> _fonts;
  late String? _pendingFont;
  late String? _previewFont;
  Timer? _searchDebounce;
  Timer? _previewDebounce;
  String _query = '';

  String? get _normalizedCurrent => _normalizeFont(widget.currentFont);

  List<_FontOption> get _filteredFonts {
    if (_query.isEmpty) return _fonts;
    return _fonts
        .where((font) => font.searchLabel.contains(_query))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _pendingFont = _normalizedCurrent;
    _previewFont = _pendingFont;

    // Font discovery can contain blank or duplicate family names. Normalize
    // and index it once instead of repeating trim/lowercase work on every
    // keystroke and every dialog rebuild.
    final seen = <String>{};
    final fonts = <_FontOption>[];
    for (final rawFont in widget.availableFonts) {
      final font = rawFont.trim();
      final searchLabel = font.toLowerCase();
      if (font.isEmpty || !seen.add(searchLabel)) continue;
      fonts.add(_FontOption(font, searchLabel));
    }
    _fonts = List.unmodifiable(fonts);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _previewDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    final normalized = value.trim().toLowerCase();
    _searchDebounce = Timer(AppMotion.fast, () {
      if (!mounted || normalized == _query) return;
      setState(() => _query = normalized);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_query.isEmpty) return;
    setState(() => _query = '');
  }

  void _select(String? font) {
    final normalized = _normalizeFont(font);
    if (_pendingFont == normalized) return;
    setState(() => _pendingFont = normalized);

    // Resolving a newly selected desktop font can block the UI thread. Keep
    // selection/checkmark feedback immediate and update only the one preview
    // after the pointer interaction has completed.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(AppMotion.fast, () {
      if (!mounted || _previewFont == normalized) return;
      setState(() => _previewFont = normalized);
    });
  }

  void _apply() {
    Navigator.of(context).pop(FontPickerResult(_pendingFont));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final filtered = _filteredFonts;
    final pendingLabel = _pendingFont ?? l10n.fontSystemDefault;
    final contentHeight =
        (MediaQuery.sizeOf(context).height - 170).clamp(300.0, 500.0);

    return AlertDialog(
      key: const Key('font-picker-dialog'),
      title: Text(l10n.fontPickerTitle),
      content: SizedBox(
        width: 380,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('font-search-field'),
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.fontSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              key: const Key('font-preview'),
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.fontPreview,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          pendingLabel,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    l10n.fontPreviewSample,
                    key: const Key('font-preview-sample'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: _previewFont,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              l10n.fontResultCount(filtered.length),
              key: const Key('font-result-count'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.xxs),
            Expanded(
              child: ListView.builder(
                key: const Key('font-list'),
                itemExtent: 48,
                cacheExtent: 144,
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final selected = _pendingFont == null;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.font_download_outlined),
                      title: Text(l10n.fontSystemDefault),
                      trailing: selected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      selected: selected,
                      onTap: () => _select(null),
                    );
                  }

                  final font = filtered[index - 1].name;
                  final selected = font == _pendingFont;
                  final builtIn = font == 'SarasaGothicSC';
                  return ListTile(
                    dense: true,
                    title: Text(
                      builtIn ? '$font · ${l10n.fontBuiltIn}' : font,
                      key: ValueKey('font-option-$font'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                    selected: selected,
                    onTap: () => _select(font),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('apply-font-selection'),
          onPressed: _pendingFont == _normalizedCurrent ? null : _apply,
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}

String? _normalizeFont(String? font) {
  final normalized = font?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

class _FontOption {
  const _FontOption(this.name, this.searchLabel);

  final String name;
  final String searchLabel;
}
