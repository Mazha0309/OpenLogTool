import 'dart:io';
import 'package:openlogtool/config/version.dart';

class AppConfig {
  static String get _commitHash {
    final envHash = Platform.environment['GITHUB_SHA'];
    if (envHash != null && envHash.isNotEmpty) {
      return envHash.length > 7 ? envHash.substring(0, 7) : envHash;
    }
    return _getGitHash();
  }

  static String get _buildNumber {
    final envBuild = Platform.environment['CI_BUILD_NUMBER'];
    if (envBuild != null && envBuild.isNotEmpty) {
      return envBuild;
    }
    final envBuildId = Platform.environment['BUILD_NUMBER'];
    if (envBuildId != null && envBuildId.isNotEmpty) {
      return envBuildId;
    }
    return '0';
  }

  static String get versionName => appVersion;
  static String get commitHash => _commitHash;
  static String get buildNumber => _buildNumber;
  static String get fullVersion => '$versionName-$commitHash-$buildNumber';

  static String _getGitHash() {
    try {
      final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return 'local';
  }

  static List<String> getSystemFonts() {
    final List<String> fonts = [];
    
    try {
      if (Platform.isLinux) {
        final result = Process.runSync('fc-list', ['--format=%{family}\n']);
        if (result.exitCode == 0) {
          final output = (result.stdout as String).trim();
          final lines = output.split('\n');
          for (final line in lines) {
            final font = line.trim();
            if (font.isNotEmpty && !fonts.contains(font)) {
              fonts.add(font);
            }
          }
        }
      } else if (Platform.isMacOS) {
        final result = Process.runSync('system_profiler', ['SPFontsDataType']);
        if (result.exitCode == 0) {
          final regex = RegExp(r'^\s*(.+?):\s*$', multiLine: true);
          final matches = regex.allMatches(result.stdout as String);
          for (final match in matches) {
            final font = match.group(1)?.trim();
            if (font != null && font.isNotEmpty && !fonts.contains(font)) {
              fonts.add(font);
            }
          }
        }
      } else if (Platform.isWindows) {
        final regResult = Process.runSync(
          'reg',
          ['query', 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts'],
        );
        if (regResult.exitCode == 0) {
          final regex = RegExp(r'^\s*(.+?)\s+\(.*\)\s*=');
          final matches = regex.allMatches(regResult.stdout as String);
          for (final match in matches) {
            final font = match.group(1)?.trim();
            if (font != null && font.isNotEmpty && !fonts.contains(font)) {
              fonts.add(font);
            }
          }
        }
      }
    } catch (_) {}

    if (fonts.isEmpty) {
      fonts.addAll(['Roboto', 'Arial', 'sans-serif']);
    }

    fonts.sort();
    return fonts;
  }
}
