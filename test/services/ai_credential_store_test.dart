import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/ai_credential_store.dart';
import 'package:openlogtool/services/secure_token_store.dart';

void main() {
  test('isolates credentials and never uses the raw profile id as a key',
      () async {
    final values = _MemorySecureValues();
    final store = AiCredentialStore(secureValues: values);

    await store.write('primary/asr', 'secret-one');
    await store.write('extractor', 'secret-two');

    expect(await store.read('primary/asr'), 'secret-one');
    expect(await store.read('extractor'), 'secret-two');
    expect(values.values.keys, hasLength(2));
    expect(
      values.values.keys,
      everyElement(startsWith('openlogtool.ai.credential.v1.')),
    );
    expect(values.values.keys.any((key) => key.contains('primary/asr')), false);
  });

  test('deleting one credential leaves other provider credentials intact',
      () async {
    final values = _MemorySecureValues();
    final store = AiCredentialStore(secureValues: values);
    await store.write('asr', 'asr-key');
    await store.write('extractor', 'extractor-key');

    await store.delete('asr');

    expect(await store.read('asr'), isNull);
    expect(await store.read('extractor'), 'extractor-key');
  });

  test('rejects empty identifiers and secrets', () async {
    final store = AiCredentialStore(secureValues: _MemorySecureValues());

    expect(() => store.read('   '), throwsArgumentError);
    expect(() => store.write('asr', ''), throwsArgumentError);
  });
}

final class _MemorySecureValues implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
