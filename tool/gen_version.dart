import 'dart:io';

void main() {
  print('=== Version Generation Started ===');
  
  final pubspec = File('pubspec.yaml');
  final content = pubspec.readAsStringSync();

  final versionMatch = RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(content);
  if (versionMatch == null) {
    print('ERROR: Could not find version in pubspec.yaml');
    exit(1);
  }

  final versionBase = versionMatch.group(1)!;
  print('Base version from pubspec.yaml: $versionBase');
  
  final commitSha = Platform.environment['CI_COMMIT_SHA'] ?? '';
  final buildNumber = Platform.environment['CI_BUILD_NUMBER'] ?? '';
  
  String appVersion;
  if (commitSha.isNotEmpty && buildNumber.isNotEmpty) {
    final shortSha = commitSha.length > 7 ? commitSha.substring(0, 7) : commitSha;
    appVersion = '$versionBase-$shortSha-$buildNumber';
    print('CI environment detected. Building full version: $appVersion');
  } else {
    appVersion = versionBase;
    print('No CI environment. Using base version: $appVersion');
  }
  
  final output = File('lib/config/version.dart');
  output.writeAsStringSync("const String appVersion = '$appVersion';\n");
  
  print('=== Version Generated Successfully ===');
  print('Generated version: $appVersion');
  print('File written: lib/config/version.dart');
}
