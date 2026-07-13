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
    return KeyedSubtree(
      key: Key(isDesktop ? 'desktop-navigation' : 'tablet-navigation'),
      child: NavigationRail(
        // Recreate the rail at its final width. Updating `extended` on the same
        // state runs Material's 200 ms width animation; because the rail is a
        // child of a Row, that forces the entire IndexedStack beside it to be
        // laid out on every tick. An atomic state swap performs one layout and
        // remains responsive even while the log table is busy.
        key: ValueKey('navigation-rail-$effectiveExpanded'),
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
              ? _DesktopRailHeader(
                  expanded: effectiveExpanded,
                  onExpandedChanged: onExpandedChanged,
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

class _DesktopRailHeader extends StatelessWidget {
  const _DesktopRailHeader({
    required this.expanded,
    required this.onExpandedChanged,
  });

  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('primary-sidebar-header'),
        height: 48,
        width: expanded ? 224 : 72,
        child: expanded
            ? Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.graphic_eq, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'OpenLogTool',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const Key('collapse-primary-sidebar'),
                    tooltip: context.l10n.collapseSidebar,
                    onPressed: () => onExpandedChanged(false),
                    icon: const Icon(Icons.keyboard_double_arrow_left),
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : Center(
                child: IconButton(
                  key: const Key('expand-primary-sidebar'),
                  tooltip: context.l10n.expandSidebar,
                  onPressed: () => onExpandedChanged(true),
                  icon: const Icon(Icons.keyboard_double_arrow_right),
                ),
              ),
      );
}
