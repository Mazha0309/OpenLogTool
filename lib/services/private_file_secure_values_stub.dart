typedef SupportDirectoryPath = Future<String> Function();

final class PlatformPrivateSecureValueBackend {
  PlatformPrivateSecureValueBackend({SupportDirectoryPath? supportDirectory});

  bool get isSupported => false;

  Future<String?> read(String key) =>
      Future.error(UnsupportedError('Private file fallback is unavailable'));

  Future<void> write(String key, String value) =>
      Future.error(UnsupportedError('Private file fallback is unavailable'));

  Future<void> delete(String key) =>
      Future.error(UnsupportedError('Private file fallback is unavailable'));
}
