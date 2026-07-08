import 'package:flutter/material.dart';

enum ShButtonVariant { primary, secondary, destructive, ghost, outline }

class ShButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ShButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final double? width;

  const ShButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ShButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (bg, fg, border) = switch (variant) {
      ShButtonVariant.primary => (c.primary, c.onPrimary, Colors.transparent),
      ShButtonVariant.secondary => (c.secondary, c.onSecondary, Colors.transparent),
      ShButtonVariant.destructive => (c.error, c.onError, Colors.transparent),
      ShButtonVariant.ghost => (Colors.transparent, c.onSurface, Colors.transparent),
      ShButtonVariant.outline => (Colors.transparent, c.onSurface, c.outlineVariant),
    };

    return SizedBox(
      width: width,
      child: TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withAlpha(128),
          disabledForegroundColor: fg.withAlpha(128),
          side: border is Color ? BorderSide(color: border) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        child: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

class ShIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const ShIconButton({super.key, required this.icon, this.onPressed, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
