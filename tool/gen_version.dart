import 'dart:io';

void main() {
  stderr.writeln('=== Version Generation Started ===');

  final pubspec = File('pubspec.yaml');
  final content = pubspec.readAsStringSync();

  final versionMatch = RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(content);
  if (versionMatch == null) {
    stderr.writeln('ERROR: Could not find version in pubspec.yaml');
    exit(1);
  }

  final versionBase = versionMatch.group(1)!;
  stderr.writeln('Base version from pubspec.yaml: $versionBase');

  final commitSha = Platform.environment['CI_COMMIT_SHA'] ?? '';
  final buildNumber = Platform.environment['CI_BUILD_NUMBER'] ?? '';

  String appVersion;
  if (commitSha.isNotEmpty && buildNumber.isNotEmpty) {
    final shortSha = commitSha.length > 7 ? commitSha.substring(0, 7) : commitSha;
    appVersion = '$versionBase-$shortSha-$buildNumber';
    stderr.writeln('CI environment detected. Building full version: $appVersion');
  } else {
    appVersion = versionBase;
    stderr.writeln('No CI environment. Using base version: $appVersion');
  }

  final output = File('lib/config/version.dart');
  output.writeAsStringSync("const String appVersion = '$appVersion';\n");

  stderr.writeln('=== Version Generated Successfully ===');
  stderr.writeln('Generated version: $appVersion');
  stderr.writeln('File written: lib/config/version.dart');
}
