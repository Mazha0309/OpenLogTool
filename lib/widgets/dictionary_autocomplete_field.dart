import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/utils/ime_safe_upper_case_formatter.dart';

class DictionaryAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hintText;
  final List<DictionaryItem> options;
  final bool upperCase;
  final bool isCompact;
  final TextInputAction? textInputAction;
  final bool enabled;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const DictionaryAutocompleteField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.label,
    required this.hintText,
    required this.options,
    this.upperCase = true,
    this.isCompact = false,
    this.textInputAction,
    this.enabled = true,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textCapitalization =
        upperCase ? TextCapitalization.characters : TextCapitalization.none;
    final inputFormatters = upperCase
        ? const [ImeSafeUpperCaseTextFormatter()]
        : const <TextInputFormatter>[];

    return Autocomplete<_DictionaryOption>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue value) {
        if (value.text.isEmpty) return const Iterable.empty();
        final query = value.text.toLowerCase();
        final scored = <_ScoredDictionaryOption>[];
        for (final option in options) {
          if (!option.matches(value.text)) continue;
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
          scored.add(_ScoredDictionaryOption(option, score));
        }
        scored.sort((a, b) {
          if (b.score != a.score) return b.score.compareTo(a.score);
          return a.option.raw.compareTo(b.option.raw);
        });
        return <_DictionaryOption>[
          for (final scoredOption in scored.take(20))
            _DictionaryOption(scoredOption.option),
        ];
      },
      displayStringForOption: (option) => option.value,
      onSelected: (_DictionaryOption selection) {
        controller.value = TextEditingValue(
          text: selection.value,
          selection: TextSelection.collapsed(offset: selection.value.length),
        );
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
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: isCompact ? 10 : 14,
            ),
          ),
          onChanged: onChanged,
          textInputAction: textInputAction ?? TextInputAction.next,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onTapOutside: (_) => fieldFocusNode.unfocus(),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<_DictionaryOption> onSelected,
        Iterable<_DictionaryOption> options,
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
                  final item = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(item.value),
                    subtitle: item.item.abbreviation.isNotEmpty ||
                            item.item.pinyin.isNotEmpty
                        ? Text(
                            [
                              if (item.item.abbreviation.isNotEmpty)
                                item.item.abbreviation,
                              if (item.item.pinyin.isNotEmpty) item.item.pinyin,
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
  }
}

class _DictionaryOption {
  final DictionaryItem item;
  _DictionaryOption(this.item);
  String get value => item.raw;
}

class _ScoredDictionaryOption {
  final DictionaryItem option;
  final int score;
  _ScoredDictionaryOption(this.option, this.score);
}
