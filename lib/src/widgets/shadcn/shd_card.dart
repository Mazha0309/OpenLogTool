import 'package:flutter/material.dart';

class ShCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? height;

  const ShCard({super.key, required this.child, this.padding, this.margin, this.height});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerTheme.color ?? const Color(0xFFE4E4E7);
    return Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}

class ShCardHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const ShCardHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
