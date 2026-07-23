import 'dart:io';

final class _VersionSpec {
  const _VersionSpec({
    required this.flutterVersion,
    required this.rustVersion,
  });

  final String flutterVersion;
  final String rustVersion;

  static _VersionSpec parse(String value) {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-R\+([1-9]\d*)$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException(
        '版本号必须使用 MAJOR.MINOR.PATCH-R+BUILD 格式，'
        '例如 2.6.3-R+15；收到：$value',
      );
    }
    return _VersionSpec(
      flutterVersion: value,
      rustVersion: value.split('+').first,
    );
  }
}

Future<void> main(List<String> arguments) async {
  try {
    final root = File.fromUri(Platform.script).absolute.parent.parent;
    if (arguments.length == 1 && arguments.single == '--check') {
      final version = _verifySynchronizedVersions(root);
      stdout.writeln('版本文件一致：${version.flutterVersion}');
      return;
    }
    if (arguments.length != 1 ||
        arguments.single == '--help' ||
        arguments.single == '-h') {
      _printUsage();
      exitCode = arguments.length == 1 ? 0 : 64;
      return;
    }

    final requested = _VersionSpec.parse(arguments.single);
    await _bumpVersion(root, requested);
  } on Object catch (error) {
    stderr.writeln('版本更新失败：$error');
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    '用法：\n'
    '  dart run tool/bump_version.dart 2.6.3-R+15\n'
    '  dart run tool/bump_version.dart --check',
  );
}

Future<void> _bumpVersion(Directory root, _VersionSpec requested) async {
  final pubspec = File('${root.path}/pubspec.yaml');
  final cargoToml = File('${root.path}/rust/Cargo.toml');
  final cargoLock = File('${root.path}/rust/Cargo.lock');
  final generatedVersion = File('${root.path}/lib/config/version.dart');
  final files = [pubspec, cargoToml, cargoLock, generatedVersion];
  final original = <File, String>{
    for (final file in files) file: file.readAsStringSync(),
  };

  try {
    pubspec.writeAsStringSync(
      _replaceSingle(
        original[pubspec]!,
        RegExp(r'^version:\s*\S+\s*$', multiLine: true),
        'version: ${requested.flutterVersion}',
        'pubspec.yaml version',
      ),
    );
    cargoToml.writeAsStringSync(
      _replaceCargoTomlVersion(
        original[cargoToml]!,
        requested.rustVersion,
      ),
    );
    cargoLock.writeAsStringSync(
      _replaceCargoLockVersion(
        original[cargoLock]!,
        packageName: 'openlogtool_core',
        version: requested.rustVersion,
      ),
    );
    generatedVersion.writeAsStringSync(
      "const String appVersion = '${requested.flutterVersion}';\n",
    );

    _verifySynchronizedVersions(root);
    stdout.writeln('正在验证 Rust 锁文件……');
    final cargo = await Process.start(
      'cargo',
      [
        'check',
        '--locked',
        '--manifest-path',
        'rust/Cargo.toml',
      ],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final cargoExitCode = await cargo.exitCode;
    if (cargoExitCode != 0) {
      throw ProcessException(
        'cargo',
        const [
          'check',
          '--locked',
          '--manifest-path',
          'rust/Cargo.toml',
        ],
        'Cargo 校验失败',
        cargoExitCode,
      );
    }
    _verifySynchronizedVersions(root);
  } on Object {
    for (final entry in original.entries) {
      entry.key.writeAsStringSync(entry.value);
    }
    rethrow;
  }

  stdout.writeln(
    '版本已更新：\n'
    '  Flutter：${requested.flutterVersion}\n'
    '  Rust：${requested.rustVersion}\n'
    '已同步 pubspec.yaml、Cargo.toml、Cargo.lock 和 version.dart。',
  );
}

_VersionSpec _verifySynchronizedVersions(Directory root) {
  final flutterVersion = _readSingleCapture(
    File('${root.path}/pubspec.yaml').readAsStringSync(),
    RegExp(r'^version:\s*(\S+)\s*$', multiLine: true),
    'pubspec.yaml version',
  );
  final expected = _VersionSpec.parse(flutterVersion);
  final cargoTomlVersion = _readCargoTomlVersion(
    File('${root.path}/rust/Cargo.toml').readAsStringSync(),
  );
  final cargoLockVersion = _readCargoLockVersion(
    File('${root.path}/rust/Cargo.lock').readAsStringSync(),
    'openlogtool_core',
  );
  final generated = _readSingleCapture(
    File('${root.path}/lib/config/version.dart').readAsStringSync(),
    RegExp(
      r"^const String appVersion = '([^']+)';\s*$",
      multiLine: true,
    ),
    'lib/config/version.dart appVersion',
  );

  final mismatches = <String>[
    if (cargoTomlVersion != expected.rustVersion)
      'rust/Cargo.toml=$cargoTomlVersion',
    if (cargoLockVersion != expected.rustVersion)
      'rust/Cargo.lock=$cargoLockVersion',
    if (generated != expected.flutterVersion)
      'lib/config/version.dart=$generated',
  ];
  if (mismatches.isNotEmpty) {
    throw StateError(
      '版本文件不一致；pubspec.yaml=${expected.flutterVersion}，'
      '${mismatches.join('，')}',
    );
  }
  return expected;
}

String _replaceSingle(
  String source,
  RegExp pattern,
  String replacement,
  String label,
) {
  final matches = pattern.allMatches(source).toList(growable: false);
  if (matches.length != 1) {
    throw StateError('$label 应恰好出现一次，实际为 ${matches.length} 次');
  }
  final match = matches.single;
  return source.replaceRange(match.start, match.end, replacement);
}

String _readSingleCapture(String source, RegExp pattern, String label) {
  final matches = pattern.allMatches(source).toList(growable: false);
  if (matches.length != 1 || matches.single.groupCount < 1) {
    throw StateError('$label 应恰好出现一次，实际为 ${matches.length} 次');
  }
  return matches.single.group(1)!;
}

String _replaceCargoTomlVersion(String source, String version) {
  final bounds = _cargoTomlPackageBounds(source);
  final packageSection = source.substring(bounds.$1, bounds.$2);
  final replaced = _replaceSingle(
    packageSection,
    RegExp(r'^version\s*=\s*"[^"]+"\s*$', multiLine: true),
    'version = "$version"',
    'rust/Cargo.toml [package] version',
  );
  return source.replaceRange(bounds.$1, bounds.$2, replaced);
}

String _readCargoTomlVersion(String source) {
  final bounds = _cargoTomlPackageBounds(source);
  return _readSingleCapture(
    source.substring(bounds.$1, bounds.$2),
    RegExp(r'^version\s*=\s*"([^"]+)"\s*$', multiLine: true),
    'rust/Cargo.toml [package] version',
  );
}

(int, int) _cargoTomlPackageBounds(String source) {
  final startMatch = RegExp(r'^\[package\]\s*$', multiLine: true)
      .allMatches(source)
      .toList(growable: false);
  if (startMatch.length != 1) {
    throw StateError(
      'rust/Cargo.toml [package] 应恰好出现一次，'
      '实际为 ${startMatch.length} 次',
    );
  }
  final start = startMatch.single.end;
  final nextSection = RegExp(r'^\[[^\]]+\]\s*$', multiLine: true)
      .firstMatch(source.substring(start));
  final end = nextSection == null ? source.length : start + nextSection.start;
  return (start, end);
}

String _replaceCargoLockVersion(
  String source, {
  required String packageName,
  required String version,
}) {
  final bounds = _cargoLockPackageBounds(source, packageName);
  final packageBlock = source.substring(bounds.$1, bounds.$2);
  final replaced = _replaceSingle(
    packageBlock,
    RegExp(r'^version\s*=\s*"[^"]+"\s*$', multiLine: true),
    'version = "$version"',
    'rust/Cargo.lock $packageName version',
  );
  return source.replaceRange(bounds.$1, bounds.$2, replaced);
}

String _readCargoLockVersion(String source, String packageName) {
  final bounds = _cargoLockPackageBounds(source, packageName);
  return _readSingleCapture(
    source.substring(bounds.$1, bounds.$2),
    RegExp(r'^version\s*=\s*"([^"]+)"\s*$', multiLine: true),
    'rust/Cargo.lock $packageName version',
  );
}

(int, int) _cargoLockPackageBounds(String source, String packageName) {
  final headers = RegExp(r'^\[\[package\]\]\s*$', multiLine: true)
      .allMatches(source)
      .toList(growable: false);
  final matching = <(int, int)>[];
  for (var index = 0; index < headers.length; index += 1) {
    final start = headers[index].start;
    final end =
        index + 1 < headers.length ? headers[index + 1].start : source.length;
    final block = source.substring(start, end);
    if (RegExp(
      '^name\\s*=\\s*"${RegExp.escape(packageName)}"\\s*\$',
      multiLine: true,
    ).hasMatch(block)) {
      matching.add((start, end));
    }
  }
  if (matching.length != 1) {
    throw StateError(
      'rust/Cargo.lock 中 $packageName 应恰好出现一次，'
      '实际为 ${matching.length} 次',
    );
  }
  return matching.single;
}
