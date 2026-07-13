import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/account_dto.dart';

void main() {
  test('parses password-change challenge details', () {
    final challenge = PasswordChangeChallengeDto.fromJson({
      'passwordChangeToken': 'change-token',
      'passwordChangeTokenExpiresIn': 300,
      'user': {
        'id': 'user-1',
        'username': 'alice',
        'role': 'user',
      },
    });

    expect(challenge.passwordChangeToken, 'change-token');
    expect(challenge.passwordChangeTokenExpiresIn, 300);
    expect(challenge.user.username, 'alice');
  });

  test('parses account and device-session timestamps as UTC', () {
    final account = AccountDto.fromJson({
      'id': 'user-1',
      'username': 'alice',
      'role': 'user',
      'mustChangePassword': false,
      'createdAt': '2026-07-13T08:00:00+08:00',
      'updatedAt': '2026-07-13T08:01:00+08:00',
      'passwordChangedAt': null,
      'usernameChangedAt': '2026-07-13T08:01:00+08:00',
    });
    final device = DeviceSessionDto.fromJson({
      'sessionId': 'refresh-1',
      'deviceId': 'device-1',
      'createdAt': '2026-07-13T08:00:00+08:00',
      'expiresAt': '2026-08-13T08:00:00+08:00',
      'lastUsedAt': null,
      'userAgent': 'OpenLogTool/1.0',
      'ipAddress': '127.0.0.1',
      'current': true,
    });

    expect(account.createdAt, DateTime.utc(2026, 7, 13));
    expect(account.user.username, 'alice');
    expect(device.createdAt, DateTime.utc(2026, 7, 13));
    expect(device.current, isTrue);
    expect(device.ipAddress, '127.0.0.1');
  });

  test('rejects malformed account protocol values', () {
    expect(
      () => AccountDto.fromJson({
        'id': 'user-1',
        'username': 'alice',
        'role': 'user',
        'mustChangePassword': 'false',
        'createdAt': '2026-07-13T00:00:00Z',
        'updatedAt': '2026-07-13T00:00:00Z',
        'passwordChangedAt': null,
        'usernameChangedAt': null,
      }),
      throwsFormatException,
    );
  });
}
