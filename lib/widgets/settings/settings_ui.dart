import 'package:flutter/material.dart';
import 'package:openlogtool/theme/app_theme.dart';

/// Visual emphasis shared by application surfaces, status pills and notices.
enum AppTone { neutral, primary, tertiary, success, warning, danger }

/// Backwards-compatible name retained while older settings-style screens move
/// to the application-wide components in this file.
typedef SettingsTone = AppTone;

enum AppSurfaceStyle { filled, outlined, tonal }

enum AppIconBadgeSize { page, section, action }

({Color foreground, Color container, Color onContainer}) _toneColors(
  BuildContext context,
  AppTone tone,
) {
  final colors = Theme.of(context).colorScheme;
  final semantic = context.semanticColors;
  return switch (tone) {
    AppTone.neutral => (
        foreground: colors.onSurfaceVariant,
        container: colors.surfaceContainerHighest,
        onContainer: colors.onSurfaceVariant,
      ),
    AppTone.primary => (
        foreground: colors.primary,
        container: colors.primaryContainer,
        onContainer: colors.onPrimaryContainer,
      ),
    AppTone.tertiary => (
        foreground: colors.tertiary,
        container: colors.tertiaryContainer,
        onContainer: colors.onTertiaryContainer,
      ),
    AppTone.success => (
        foreground: semantic.success,
        container: semantic.successContainer,
        onContainer: semantic.onSuccessContainer,
      ),
    AppTone.warning => (
        foreground: semantic.warning,
        container: semantic.warningContainer,
        onContainer: semantic.onWarningContainer,
      ),
    AppTone.danger => (
        foreground: colors.error,
        container: colors.errorContainer,
        onContainer: colors.onErrorContainer,
      ),
  };
}

/// The single scroll owner and horizontal alignment rule for standard pages.
class AppPageFrame extends StatelessWidget {
  const AppPageFrame({
    super.key,
    required this.child,
    this.header,
    this.maxWidth = AppDimensions.standardContentWidth,
    this.scrollKey,
    this.controller,
  });

  final Widget child;
  final Widget? header;
  final double maxWidth;
  final Key? scrollKey;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.compact;
          return SingleChildScrollView(
            key: scrollKey,
            controller: controller,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              compact ? AppSpace.sm : AppSpace.lg,
              compact ? AppSpace.md : AppSpace.lg,
              compact ? AppSpace.sm : AppSpace.lg,
              AppSpace.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (header case final header?) ...[
                      header,
                      const SizedBox(height: AppSpace.lg),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.tone = AppTone.primary,
    this.size = AppIconBadgeSize.section,
  });

  final IconData icon;
  final AppTone tone;
  final AppIconBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final toneColors = _toneColors(context, tone);
    final (dimension, iconSize, radius) = switch (size) {
      AppIconBadgeSize.page => (
          AppDimensions.pageIcon,
          24.0,
          AppRadius.control,
        ),
      AppIconBadgeSize.section => (
          AppDimensions.sectionIcon,
          20.0,
          AppRadius.small + 2,
        ),
      AppIconBadgeSize.action => (
          AppDimensions.actionIcon,
          18.0,
          AppRadius.small,
        ),
    };
    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        color: toneColors.container,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: toneColors.onContainer),
    );
  }
}

/// Responsive title block used once at the top of a page.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    this.actions = const <Widget>[],
  });

  final String title;
  final String description;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final introduction = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon case final icon?) ...[
          AppIconBadge(icon: icon, size: AppIconBadgeSize.page),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (actions.isEmpty) return introduction;

    final actionWrap = Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      alignment: WrapAlignment.end,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              introduction,
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: actionWrap,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: introduction),
            const SizedBox(width: AppSpace.lg),
            Flexible(child: actionWrap),
          ],
        );
      },
    );
  }
}

/// Compatibility wrapper for screens not yet renamed to [AppPageHeader].
class SettingsPageHeader extends AppPageHeader {
  const SettingsPageHeader({
    super.key,
    required super.title,
    required super.description,
    super.icon,
    super.actions,
  });
}

/// A calm, flat section surface matching the visual hierarchy of About.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.description,
    this.padding = AppSpace.md,
    this.contentSpacing = AppSpace.sm,
    this.tone = AppTone.primary,
    this.headerTrailing,
    this.style = AppSurfaceStyle.filled,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget child;
  final double padding;
  final double contentSpacing;
  final AppTone tone;
  final Widget? headerTrailing;
  final AppSurfaceStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final toneColors = _toneColors(context, tone);
    final tonal = style == AppSurfaceStyle.tonal;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconBadge(icon: icon, tone: tone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tonal ? toneColors.onContainer : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (description case final description?) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tonal
                        ? toneColors.onContainer
                        : colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final border = style == AppSurfaceStyle.outlined
        ? BorderSide(color: colors.outlineVariant)
        : BorderSide.none;
    final background = switch (style) {
      AppSurfaceStyle.filled => colors.surfaceContainerLow,
      AppSurfaceStyle.outlined => colors.surface,
      AppSurfaceStyle.tonal => toneColors.container,
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.surface),
        side: border,
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final trailing = headerTrailing;
                if (trailing == null) return heading;
                // Action groups (for example session state + rename + create)
                // can be substantially wider than a single icon button. Keep
                // them below the heading until the card has true desktop room
                // instead of allowing the title row to collapse below the
                // fixed icon badge width.
                if (constraints.maxWidth < AppBreakpoints.cardHeaderStack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: AppSpace.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: trailing,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: AppSpace.sm),
                    trailing,
                  ],
                );
              },
            ),
            SizedBox(height: contentSpacing),
            child,
          ],
        ),
      ),
    );
  }
}

/// Compatibility wrapper retaining the outlined settings-card appearance.
class SettingsSectionCard extends AppSectionCard {
  const SettingsSectionCard({
    super.key,
    required super.icon,
    required super.title,
    required super.child,
    super.description,
    super.padding,
    super.contentSpacing,
    super.tone,
    super.headerTrailing,
    super.style = AppSurfaceStyle.outlined,
  });
}

/// A setting/action row that moves its trailing control below the copy when
/// the available width cannot accommodate both without compression.
class AppActionTile extends StatelessWidget {
  const AppActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.busy = false,
    this.tone = AppTone.primary,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpace.xxs,
      vertical: AppSpace.xs,
    ),
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;
  final AppTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final toneColors = _toneColors(context, tone);
    final effectiveEnabled = enabled && !busy;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = trailing != null && constraints.maxWidth < 480;
        final copy = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon case final icon?) ...[
              Opacity(
                opacity: effectiveEnabled ? 1 : 0.45,
                child: AppIconBadge(
                  icon: icon,
                  tone: tone,
                  size: AppIconBadgeSize.action,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: effectiveEnabled
                          ? (tone == AppTone.danger
                              ? toneColors.foreground
                              : null)
                          : theme.disabledColor,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: effectiveEnabled
                          ? (tone == AppTone.danger
                              ? toneColors.foreground
                              : colors.onSurfaceVariant)
                          : theme.disabledColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final progress = SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: toneColors.foreground,
          ),
        );
        final content = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: AppSpace.sm),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: busy ? progress : trailing!,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: copy),
                  if (busy) ...[
                    const SizedBox(width: AppSpace.sm),
                    progress,
                  ] else if (trailing case final trailing?) ...[
                    const SizedBox(width: AppSpace.sm),
                    trailing,
                  ],
                ],
              );

        return Semantics(
          button: onTap != null,
          enabled: effectiveEnabled,
          child: InkWell(
            onTap: effectiveEnabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: IgnorePointer(
              ignoring: !effectiveEnabled,
              child: Padding(padding: padding, child: content),
            ),
          ),
        );
      },
    );
  }
}

class SettingsActionTile extends AppActionTile {
  const SettingsActionTile({
    super.key,
    required super.title,
    required super.subtitle,
    super.icon,
    super.trailing,
    super.onTap,
    super.enabled,
    super.busy,
    super.tone,
    super.padding,
  });
}

class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.label, {super.key, this.tone = AppTone.neutral});

  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final toneColors = _toneColors(context, tone);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpace.xxs,
        bottom: AppSpace.xxs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone == AppTone.neutral
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : toneColors.foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class SettingsSectionLabel extends AppSectionLabel {
  const SettingsSectionLabel(
    super.label, {
    super.key,
    super.tone = AppTone.neutral,
  });
}

class AppTileGroup extends StatelessWidget {
  const AppTileGroup({
    super.key,
    required this.children,
    this.dividerIndent = AppDimensions.actionIcon + AppSpace.sm + AppSpace.xxs,
  });

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(height: 1, indent: dividerIndent),
          ],
        ],
      );
}

class SettingsTileGroup extends AppTileGroup {
  const SettingsTileGroup({
    super.key,
    required super.children,
    super.dividerIndent,
  });
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
  });

  final String label;
  final IconData? icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final toneColors = _toneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: toneColors.container,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 16, color: toneColors.onContainer),
            const SizedBox(width: AppSpace.xs),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: toneColors.onContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline,
    this.tone = AppTone.neutral,
    this.trailing,
  });

  final String? title;
  final String message;
  final IconData icon;
  final AppTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final toneColors = _toneColors(context, tone);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: toneColors.container,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: toneColors.onContainer),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title case final title?) ...[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: toneColors.onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: toneColors.onContainer,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: AppSpace.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
