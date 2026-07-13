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
    return NavigationRail(
      key: Key(isDesktop ? 'desktop-navigation' : 'tablet-navigation'),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: effectiveExpanded,
      labelType: effectiveExpanded
          ? NavigationRailLabelType.none
          : isDesktop
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.selected,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: isDesktop
            ? effectiveExpanded
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        'OpenLogTool',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('collapse-primary-sidebar'),
                        tooltip: context.l10n.collapseSidebar,
                        onPressed: () => onExpandedChanged(false),
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq, size: 28),
                      const SizedBox(height: 6),
                      IconButton(
                        key: const Key('expand-primary-sidebar'),
                        tooltip: context.l10n.expandSidebar,
                        onPressed: () => onExpandedChanged(true),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  )
            : const Icon(Icons.graphic_eq, size: 28),
      ),
      destinations: destinations,
    );
  }
}
