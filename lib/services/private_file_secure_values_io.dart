import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef SupportDirectoryPath = Future<String> Function();

/// Linux-only persistence used when no Secret Service/keyring is available.
///
/// Secrets are written only after the containing directory and an empty
/// temporary file have been restricted to the current user. The temporary file
/// is then atomically renamed over the live file.
final class PlatformPrivateSecureValueBackend {
  PlatformPrivateSecureValueBackend({SupportDirectoryPath? supportDirectory})
      : _supportDirectory =
            supportDirectory ?? _defaultApplicationSupportDirectory;

  final SupportDirectoryPath _supportDirectory;
  Future<void> _operationTail = Future<void>.value();
  int _temporaryFileSequence = 0;

  bool get isSupported => Platform.isLinux;

  Future<String?> read(String key) =>
      _synchronized(() async => (await _readValues())[key]);

  Future<void> write(String key, String value) => _synchronized(() async {
        final values = await _readValues();
        values[key] = value;
        await _writeValues(values);
      });

  Future<void> delete(String key) => _synchronized(() async {
        final values = await _readValues();
        if (values.remove(key) == null) return;
        if (values.isEmpty) {
          final file = await _valuesFile();
          if (await file.exists()) await file.delete();
          return;
        }
        await _writeValues(values);
      });

  Future<T> _synchronized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<Map<String, String>> _readValues() async {
    final file = await _valuesFile();
    if (!await file.exists()) return <String, String>{};
    await _restrict(file.path, '600');
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
            'Private credential file must be an object');
      }
      return decoded.map((key, value) {
        if (value is! String) {
          throw const FormatException(
            'Private credential values must be strings',
          );
        }
        return MapEntry(key, value);
      });
    } on FormatException {
      // A partial or manually damaged file must not prevent app startup or
      // expose a mixture of stale credentials.
      await file.delete();
      return <String, String>{};
    }
  }

  Future<void> _writeValues(Map<String, String> values) async {
    final file = await _valuesFile();
    final temporary = File(
      '${file.path}.${pid}_${_temporaryFileSequence++}.tmp',
    );
    await temporary.create();
    try {
      // The file is still empty here, so no secret is briefly exposed with the
      // process umask's broader default mode.
      await _restrict(temporary.path, '600');
      await temporary.writeAsString(jsonEncode(values), flush: true);
      await temporary.rename(file.path);
      await _restrict(file.path, '600');
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<File> _valuesFile() async {
    if (!isSupported) {
      throw UnsupportedError('Private file fallback is Linux-only');
    }
    final supportPath = await _supportDirectory();
    final directory = Directory(
      p.join(supportPath, 'secure_storage_fallback'),
    );
    await directory.create(recursive: true);
    await _restrict(directory.path, '700');
    return File(p.join(directory.path, 'auth_sessions.json'));
  }

  Future<void> _restrict(String path, String mode) async {
    final result = await Process.run('chmod', <String>[mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Unable to restrict private credential storage to mode $mode: '
        '${result.stderr}',
        path,
      );
    }
  }

  static Future<String> _defaultApplicationSupportDirectory() async =>
      (await getApplicationSupportDirectory()).path;
}
