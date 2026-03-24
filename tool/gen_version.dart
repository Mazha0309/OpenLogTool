import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml');
  final content = pubspec.readAsStringSync();

  final versionMatch = RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(content);
  if (versionMatch == null) {
    print('Could not find version in pubspec.yaml');
    exit(1);
  }

  final version = versionMatch.group(1)!;

  final output = File('lib/config/version.dart');
  output.writeAsStringSync("const String appVersion = '$version';\n");

  print('Generated version: $version');
}
