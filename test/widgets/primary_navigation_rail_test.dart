import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/primary_navigation_rail.dart';

void main() {
  testWidgets('desktop rail can collapse and expand', (tester) async {
    var contentLayoutCount = 0;
    await tester.pumpWidget(
      _RailHarness(
        locale: const Locale('zh', 'CN'),
        isDesktop: true,
        initiallyExpanded: true,
        onContentLayout: () => contentLayoutCount += 1,
      ),
    );

    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue);
    final collapse = tester.widget<IconButton>(
      find.byKey(const Key('collapse-primary-sidebar')),
    );
    expect(collapse.tooltip, '收起侧边栏');
    expect(find.text('OpenLogTool'), findsOneWidget);
    final expandedHeaderSize =
        tester.getSize(find.byKey(const Key('primary-sidebar-header')));
    final expandedRailWidth =
        tester.getSize(find.byKey(const Key('desktop-navigation'))).width;
    final expandedRailState = tester.state(find.byType(NavigationRail));
    final layoutsBeforeCollapse = contentLayoutCount;

    collapse.onPressed!();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('desktop-navigation'))).width,
      lessThan(expandedRailWidth),
    );
    expect(
      tester.getSize(find.byKey(const Key('primary-sidebar-header'))).height,
      expandedHeaderSize.height,
    );
    expect(tester.state(find.byType(NavigationRail)),
        isNot(same(expandedRailState)));
    expect(contentLayoutCount, greaterThan(layoutsBeforeCollapse));
    final layoutsAfterAtomicSwitch = contentLayoutCount;

    // Additional frames must not keep changing the adjacent content width.
    // NavigationRail's normal extended animation would lay it out on each pump.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 160));
    expect(contentLayoutCount, layoutsAfterAtomicSwitch);
    expect(tester.hasRunningAnimations, isFalse);

    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isFalse);
    expect(find.text('OpenLogTool'), findsNothing);
    final expand = tester.widget<IconButton>(
      find.byKey(const Key('expand-primary-sidebar')),
    );
    expect(expand.tooltip, '展开侧边栏');

    expand.onPressed!();
    await tester.pump();
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue);
    expect(
      tester.getSize(find.byKey(const Key('desktop-navigation'))).width,
      expandedRailWidth,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('tablet remains compact and has no manual toggle',
      (tester) async {
    await tester.pumpWidget(
      const _RailHarness(
        locale: Locale('en', 'US'),
        isDesktop: false,
        initiallyExpanded: true,
      ),
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.selected);
    expect(find.byKey(const Key('collapse-primary-sidebar')), findsNothing);
    expect(find.byKey(const Key('expand-primary-sidebar')), findsNothing);
    expect(find.byKey(const Key('tablet-navigation')), findsOneWidget);
  });
}

class _RailHarness extends StatefulWidget {
  const _RailHarness({
    required this.locale,
    required this.isDesktop,
    required this.initiallyExpanded,
    this.onContentLayout,
  });

  final Locale locale;
  final bool isDesktop;
  final bool initiallyExpanded;
  final VoidCallback? onContentLayout;

  @override
  State<_RailHarness> createState() => _RailHarnessState();
}

class _RailHarnessState extends State<_RailHarness> {
  late bool expanded = widget.initiallyExpanded;
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: widget.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              PrimaryNavigationRail(
                isDesktop: widget.isDesktop,
                expanded: expanded,
                selectedIndex: selectedIndex,
                onDestinationSelected: (value) =>
                    setState(() => selectedIndex = value),
                onExpandedChanged: (value) => setState(() => expanded = value),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.radio_outlined),
                    label: Text('One'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: Text('Two'),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    widget.onContentLayout?.call();
                    return const SizedBox.expand();
                  },
                ),
              ),
            ],
          ),
        ),
      );
}
