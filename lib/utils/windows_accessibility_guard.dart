import 'dart:io';

import 'package:flutter/widgets.dart';

const _windowsAccessibilityOverride =
    'OPENLOGTOOL_ENABLE_WINDOWS_ACCESSIBILITY';

/// Returns whether the Windows accessibility-tree compatibility guard should
/// be enabled for this process.
///
/// Flutter's Windows accessibility bridge can dereference a semantic node
/// after it has been reparented while Windows 10 UI Automation clients are
/// observing a responsive rebuild. The failure is native and terminates the
/// process before Dart can report it. Windows 11 uses a newer UI Automation
/// stack and is left unchanged. Setting
/// `OPENLOGTOOL_ENABLE_WINDOWS_ACCESSIBILITY=1` explicitly opts back into the
/// full semantics tree for screen-reader users.
@visibleForTesting
bool shouldGuardWindowsAccessibility({
  String? operatingSystem,
  String? operatingSystemVersion,
  Map<String, String>? environment,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os != 'windows') return false;

  final processEnvironment = environment ?? Platform.environment;
  if (processEnvironment[_windowsAccessibilityOverride] == '1') return false;

  final version = operatingSystemVersion ?? Platform.operatingSystemVersion;
  final match = RegExp(r'(?:10\.0\.|Build\s+)(\d{5})').firstMatch(version);
  final build = match == null ? null : int.tryParse(match.group(1)!);
  // Unknown Windows versions use the safer behavior. Windows 11 starts at
  // build 22000.
  return build == null || build < 22000;
}

/// Prevents Windows 10 UI Automation clients from activating Flutter's
/// unstable, rapidly changing semantics tree.
class WindowsAccessibilityCrashGuard extends StatelessWidget {
  const WindowsAccessibilityCrashGuard({
    required this.child,
    this.enabled,
    super.key,
  });

  final Widget child;
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? shouldGuardWindowsAccessibility())) return child;
    return ExcludeSemantics(child: child);
  }
}
