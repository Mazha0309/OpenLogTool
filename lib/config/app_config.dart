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

  static String get versionName {
    final parts = appVersion.split('-');
    return parts.isNotEmpty ? parts[0] : appVersion;
  }
  
  static String get commitHash => _commitHash;

  static String get buildNumber => _buildNumber;
  
  static String get fullVersion => appVersion;

  static String _getGitHash() {
    try {
      final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return 'local';
  }

  static Future<List<String>> getSystemFonts() async {
    final Set<String> fonts = {};

    try {
      if (Platform.isLinux) {
        final result = await Process.run('fc-list', ['--format=%{family}\n']);
        if (result.exitCode == 0) {
          final output = (result.stdout as String).trim();
          final lines = output.split('\n');
          for (final line in lines) {
            final primary = _extractPrimaryFamily(line);
            if (primary != null) {
              fonts.add(primary);
            }
          }
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('system_profiler', ['SPFontsDataType']);
        if (result.exitCode == 0) {
          final regex = RegExp(r'^\s*(.+?):\s*$', multiLine: true);
          final matches = regex.allMatches(result.stdout as String);
          for (final match in matches) {
            final font = match.group(1)?.trim();
            if (font != null && font.isNotEmpty && !_isStyleVariant(font)) {
              fonts.add(font);
            }
          }
        }
      } else if (Platform.isWindows) {
        final regResult = await Process.run(
          'reg',
          ['query', 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts'],
        );
        if (regResult.exitCode == 0) {
          final regex = RegExp(r'^\s*(.+?)\s+\(.*\)\s*=');
          final matches = regex.allMatches(regResult.stdout as String);
          for (final match in matches) {
            final font = match.group(1)?.trim();
            if (font != null && font.isNotEmpty && !_isStyleVariant(font)) {
              fonts.add(font);
            }
          }
        }
      }
    } catch (_) {}

    if (fonts.isEmpty) {
      fonts.addAll(['SarasaGothicSC', 'Roboto', 'Arial', 'sans-serif']);
    }

    fonts.add('SarasaGothicSC');

    final sorted = fonts.toList()..sort();
    sorted.remove('SarasaGothicSC');
    sorted.insert(0, 'SarasaGothicSC');
    return sorted;
  }

  /// 从 fc-list 的一行输出里提取主 family 名。
  /// 例如 "Inter,Inter ExtraLight" 只保留 "Inter"；过滤掉变体。
  static String? _extractPrimaryFamily(String line) {
    final raw = line.trim();
    if (raw.isEmpty) return null;

    final parts = raw.split(',');
    for (final part in parts) {
      final family = part.trim();
      if (family.isEmpty) continue;
      if (_isStyleVariant(family)) continue;
      return family;
    }
    return null;
  }

  /// 把用户保存的字体名标准化为主 family。
  /// 例如 "更纱黑体 SC,Sarasa Gothic SC" -> "更纱黑体 SC"。
  static String normalizeFontFamily(String? font) {
    if (font == null || font.isEmpty) return '';
    final primary = _extractPrimaryFamily(font);
    return primary ?? font;
  }

  /// 判断是否像 "Bold" / "Italic" / "Light" 等字重/样式变体。
  static bool _isStyleVariant(String name) {
    final lower = name.toLowerCase();
    const variants = [
      'bold', 'italic', 'oblique', 'light', 'regular',
      'medium', 'black', 'thin', 'heavy', 'condensed',
      'expanded', 'semi', 'extra', 'ultra', 'narrow',
    ];
    return variants.any((v) => lower.contains(v));
  }
}
