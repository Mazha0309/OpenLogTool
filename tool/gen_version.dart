import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml');
  final content = pubspec.readAsStringSync();

  final versionMatch = RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(content);
  if (versionMatch == null) {
    print('Could not find version in pubspec.yaml');
    exit(1);
  }

  final versionBase = versionMatch.group(1)!;
  final versionName = Platform.environment['VERSION_NAME'] ?? versionBase;
  final commitSha = Platform.environment['CI_COMMIT_SHA'] ?? '';
  final buildNumber = Platform.environment['CI_BUILD_NUMBER'] ?? '';
  
  String appVersion;
  if (commitSha.isNotEmpty && buildNumber.isNotEmpty) {
    final shortSha = commitSha.length > 7 ? commitSha.substring(0, 7) : commitSha;
    appVersion = '$versionName-$shortSha-$buildNumber';
  } else {
    appVersion = versionName;
  }

  final output = File('lib/config/version.dart');
  output.writeAsStringSync("const String appVersion = '$appVersion';\n");

  print('Generated version: $appVersion');
}
