import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/windows_accessibility_guard.dart';

void main() {
  test('guards Windows 10 but not Windows 11', () {
    expect(
      shouldGuardWindowsAccessibility(
        operatingSystem: 'windows',
        operatingSystemVersion: 'Microsoft Windows [Version 10.0.19045.5965]',
        environment: const {},
      ),
      isTrue,
    );
    expect(
      shouldGuardWindowsAccessibility(
        operatingSystem: 'windows',
        operatingSystemVersion: 'Microsoft Windows [Version 10.0.26100.4652]',
        environment: const {},
      ),
      isFalse,
    );
  });

  test('explicit accessibility opt-in disables the guard', () {
    expect(
      shouldGuardWindowsAccessibility(
        operatingSystem: 'windows',
        operatingSystemVersion: '10.0.19045',
        environment: const {
          'OPENLOGTOOL_ENABLE_WINDOWS_ACCESSIBILITY': '1',
        },
      ),
      isFalse,
    );
  });

  test('does not guard other platforms', () {
    expect(
      shouldGuardWindowsAccessibility(
        operatingSystem: 'linux',
        operatingSystemVersion: 'Linux',
        environment: const {},
      ),
      isFalse,
    );
  });

  testWidgets('guard excludes descendant semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const WindowsAccessibilityCrashGuard(
        enabled: true,
        child: MaterialApp(
          home: Scaffold(
            body: TextField(
              decoration: InputDecoration(labelText: 'Callsign'),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Callsign'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    semantics.dispose();
  });
}
