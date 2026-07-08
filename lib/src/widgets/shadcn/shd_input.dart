import 'package:flutter/material.dart';

class ShInput extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  const ShInput({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
          ),
        TextField(
          controller: controller,
          onChanged: onChanged,
          focusNode: focusNode,
          autofocus: autofocus,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class ShDropdown extends StatelessWidget {
  final String? label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;

  const ShDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerTheme.color ?? const Color(0xFFE4E4E7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: theme.textTheme.bodyMedium))).toList(),
              onChanged: onChanged,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
