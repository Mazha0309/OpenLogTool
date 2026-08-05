import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/generated/app_localizations_en.dart';
import 'package:openlogtool/l10n/generated/app_localizations_zh.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/utils/server_connection_error.dart';

void main() {
  const url = 'http://example.test:3000';

  test('network errors are actionable and do not expose the exception object',
      () {
    const error = ServerApiException(
      error: ApiErrorDto(
        code: 'NETWORK_ERROR',
        message: 'The server request failed',
        requestId: 'client',
      ),
      statusCode: null,
      retryable: true,
    );

    final zh = localizedServerConnectionError(
      l10n: AppLocalizationsZh(),
      serverUrl: url,
      error: error,
    );
    final en = localizedServerConnectionError(
      l10n: AppLocalizationsEn(),
      serverUrl: url,
      error: error,
    );

    expect(zh, contains(url));
    expect(zh, contains('服务端或反向代理正在运行'));
    expect(en, contains(url));
    expect(en, contains('server or reverse proxy is running'));
    expect(zh, isNot(contains('ServerApiException')));
    expect(en, isNot(contains('ServerApiException')));
  });

  test('empty and malformed addresses get localized validation guidance', () {
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();

    expect(
      localizedServerConnectionError(
        l10n: zh,
        serverUrl: '',
        error: StateError('not configured'),
      ),
      '连接失败：请先填写服务器地址。',
    );
    expect(
      localizedServerConnectionError(
        l10n: en,
        serverUrl: 'example.test:3000',
        error: StateError('invalid URL'),
      ),
      'Connection failed: The server address must be a complete http(s) URL.',
    );
  });

  test('web mixed-content errors explain that HTTPS is required', () {
    const error = ServerApiException(
      error: ApiErrorDto(
        code: 'NETWORK_ERROR',
        message: 'The server request failed',
        requestId: 'client',
      ),
      statusCode: null,
      retryable: true,
    );

    final message = localizedServerConnectionError(
      l10n: AppLocalizationsZh(),
      serverUrl: 'http://api.example.test',
      error: error,
      isWeb: true,
      pageUri: Uri.parse('https://log.example.test/settings'),
    );

    expect(message, contains('WebClient 使用 HTTPS'));
    expect(message, contains('HTTP 服务器'));
  });

  test('web cross-origin errors explain the server allowlist', () {
    const error = ServerApiException(
      error: ApiErrorDto(
        code: 'NETWORK_ERROR',
        message: 'The server request failed',
        requestId: 'client',
      ),
      statusCode: null,
      retryable: true,
    );

    final message = localizedServerConnectionError(
      l10n: AppLocalizationsZh(),
      serverUrl: 'https://api.example.test',
      error: error,
      isWeb: true,
      pageUri: Uri.parse('https://log.example.test/settings'),
    );

    expect(message, contains('CORS_ORIGINS'));
    expect(message, contains('https://log.example.test'));
  });
}
