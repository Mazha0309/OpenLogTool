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
}
