import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/deployed_config_stub.dart';

void main() {
  test('unset or placeholder meta content is ignored', () {
    expect(defaultServerUrlFromMeta(null), isNull);
    expect(defaultServerUrlFromMeta(''), isNull);
    expect(defaultServerUrlFromMeta('   '), isNull);
    expect(defaultServerUrlFromMeta('__APP_DEFAULT_SERVER_URL__'), isNull);
  });

  test('injected server url is returned trimmed', () {
    expect(
      defaultServerUrlFromMeta(' https://api.mazha0309.com '),
      'https://api.mazha0309.com',
    );
  });

  test('stub platform has no deployed default', () {
    expect(deployedDefaultServerUrl(), isNull);
  });
}
