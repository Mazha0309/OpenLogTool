import 'dart:io';

void main() {
  print('=== Environment Variables ===');
  print('VERSION_NAME: ${Platform.environment['VERSION_NAME'] ?? "NOT SET"}');
  print('CI_COMMIT_SHA: ${Platform.environment['CI_COMMIT_SHA'] ?? "NOT SET"}');
  print('CI_BUILD_NUMBER: ${Platform.environment['CI_BUILD_NUMBER'] ?? "NOT SET"}');
  
  final pubspec = File('pubspec.yaml');
  final content = pubspec.readAsStringSync();

  final versionMatch = RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(content);
  if (versionMatch == null) {
    print('Could not find version in pubspec.yaml');
    exit(1);
  }

  final versionBase = versionMatch.group(1)!;
  print('pubspec version: $versionBase');
  
  final envVersionName = Platform.environment['VERSION_NAME'];
  final versionName = (envVersionName != null && envVersionName.isNotEmpty) 
      ? envVersionName 
      : versionBase;
  print('Using versionName: $versionName (envVersionName was: [$envVersionName])');
  
  final commitSha = Platform.environment['CI_COMMIT_SHA'] ?? '';
  final buildNumber = Platform.environment['CI_BUILD_NUMBER'] ?? '';
  
  String appVersion;
  if (commitSha.isNotEmpty && buildNumber.isNotEmpty) {
    final shortSha = commitSha.length > 7 ? commitSha.substring(0, 7) : commitSha;
    appVersion = '$versionName-$shortSha-$buildNumber';
  } else {
    appVersion = versionName;
  }

  if (appVersion.isEmpty) {
    appVersion = versionBase;
    print('WARNING: appVersion was empty, using versionBase: $appVersion');
  }
  
  if (appVersion.isEmpty) {
    print('ERROR: Even versionBase is empty! pubspec.yaml might be corrupted.');
    exit(1);
  }
  
  print('Final appVersion: $appVersion');
  
  final output = File('lib/config/version.dart');
  output.writeAsStringSync("const String appVersion = '$appVersion';\n");

  print('Generated version: $appVersion');
  print('=== File Content ===');
  print(output.readAsStringSync());
  
  if (output.readAsStringSync() != "const String appVersion = '$appVersion';\n") {
    print('ERROR: File was not written correctly!');
    exit(1);
  }
}
