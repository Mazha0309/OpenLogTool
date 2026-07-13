import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';

/// Responsive primary rail used by tablet and desktop layouts.
///
/// Tablet stays compact. Only desktop exposes the persisted expand/collapse
/// control supplied by the parent.
class PrimaryNavigationRail extends StatelessWidget {
  const PrimaryNavigationRail({
    super.key,
    required this.isDesktop,
    required this.expanded,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onExpandedChanged,
    required this.destinations,
  });

  final bool isDesktop;
  final bool expanded;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<bool> onExpandedChanged;
  final List<NavigationRailDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final effectiveExpanded = isDesktop && expanded;
    return RepaintBoundary(
      child: NavigationRail(
        key: Key(isDesktop ? 'desktop-navigation' : 'tablet-navigation'),
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        extended: effectiveExpanded,
        minWidth: 72,
        minExtendedWidth: 224,
        labelType: effectiveExpanded
            ? NavigationRailLabelType.none
            : isDesktop
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.selected,
        leadingAtTop: true,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: isDesktop
              ? Builder(
                  builder: (context) => _AnimatedDesktopRailHeader(
                    animation: NavigationRail.extendedAnimation(context),
                    expanded: expanded,
                    onExpandedChanged: onExpandedChanged,
                  ),
                )
              : const SizedBox(
                  height: 48,
                  child: Center(child: Icon(Icons.graphic_eq, size: 28)),
                ),
        ),
        destinations: destinations,
      ),
    );
  }
}

/// Uses the rail's own width animation instead of swapping between a row and a
/// column at the start of the transition. The old swap changed the header's
/// height immediately while the rail was still animating, which caused the
/// destinations and content pane to visibly jump.
class _AnimatedDesktopRailHeader extends StatelessWidget {
  const _AnimatedDesktopRailHeader({
    required this.animation,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final Animation<double> animation;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('primary-sidebar-header'),
        height: 48,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final progress = animation.value;
            return SizedBox(
              width: 72 + (152 * progress),
              child: ClipRect(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (progress > 0)
                      Positioned(
                        left: 16,
                        right: 52,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: progress,
                          child: const Row(
                            children: [
                              Icon(Icons.graphic_eq, size: 26),
                              SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'OpenLogTool',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.lerp(
                        Alignment.center,
                        Alignment.centerRight,
                        progress,
                      )!,
                      child: Padding(
                        padding: EdgeInsets.only(right: progress * 4),
                        child: IconButton(
                          key: Key(
                            expanded
                                ? 'collapse-primary-sidebar'
                                : 'expand-primary-sidebar',
                          ),
                          tooltip: expanded
                              ? context.l10n.collapseSidebar
                              : context.l10n.expandSidebar,
                          onPressed: () => onExpandedChanged(!expanded),
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_double_arrow_left
                                : Icons.keyboard_double_arrow_right,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
