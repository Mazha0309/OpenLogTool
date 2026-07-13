import 'package:openlogtool/models/collaboration_dto.dart';

typedef AccountJsonObject = Map<String, Object?>;

final class PasswordChangeChallengeDto {
  const PasswordChangeChallengeDto({
    required this.passwordChangeToken,
    required this.passwordChangeTokenExpiresIn,
    required this.user,
  });

  factory PasswordChangeChallengeDto.fromJson(Object? json) {
    final object = _object(json, 'passwordChangeChallenge');
    return PasswordChangeChallengeDto(
      passwordChangeToken: _string(object, 'passwordChangeToken'),
      passwordChangeTokenExpiresIn:
          _integer(object, 'passwordChangeTokenExpiresIn'),
      user: ApiUserDto.fromJson(object['user']),
    );
  }

  final String passwordChangeToken;
  final int passwordChangeTokenExpiresIn;
  final ApiUserDto user;

  AccountJsonObject toJson() => {
        'passwordChangeToken': passwordChangeToken,
        'passwordChangeTokenExpiresIn': passwordChangeTokenExpiresIn,
        'user': user.toJson(),
      };
}

final class AccountDto {
  const AccountDto({
    required this.id,
    required this.username,
    required this.role,
    required this.mustChangePassword,
    required this.createdAt,
    required this.updatedAt,
    required this.passwordChangedAt,
    required this.usernameChangedAt,
  });

  factory AccountDto.fromJson(Object? json) {
    final object = _object(json, 'account');
    return AccountDto(
      id: _string(object, 'id'),
      username: _string(object, 'username'),
      role: _string(object, 'role'),
      mustChangePassword: _boolean(object, 'mustChangePassword'),
      createdAt: _dateTime(object, 'createdAt'),
      updatedAt: _dateTime(object, 'updatedAt'),
      passwordChangedAt: _nullableDateTime(object, 'passwordChangedAt'),
      usernameChangedAt: _nullableDateTime(object, 'usernameChangedAt'),
    );
  }

  final String id;
  final String username;
  final String role;
  final bool mustChangePassword;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? passwordChangedAt;
  final DateTime? usernameChangedAt;

  ApiUserDto get user => ApiUserDto(id: id, username: username, role: role);

  AccountJsonObject toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'mustChangePassword': mustChangePassword,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'passwordChangedAt': passwordChangedAt?.toUtc().toIso8601String(),
        'usernameChangedAt': usernameChangedAt?.toUtc().toIso8601String(),
      };
}

final class DeviceSessionDto {
  const DeviceSessionDto({
    required this.sessionId,
    required this.deviceId,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.userAgent,
    required this.ipAddress,
    required this.current,
  });

  factory DeviceSessionDto.fromJson(Object? json) {
    final object = _object(json, 'deviceSession');
    return DeviceSessionDto(
      sessionId: _string(object, 'sessionId'),
      deviceId: _nullableString(object, 'deviceId'),
      createdAt: _dateTime(object, 'createdAt'),
      expiresAt: _dateTime(object, 'expiresAt'),
      lastUsedAt: _nullableDateTime(object, 'lastUsedAt'),
      userAgent: _nullableString(object, 'userAgent'),
      ipAddress: _nullableString(object, 'ipAddress'),
      current: _boolean(object, 'current'),
    );
  }

  final String sessionId;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastUsedAt;
  final String? userAgent;
  final String? ipAddress;
  final bool current;

  AccountJsonObject toJson() => {
        'sessionId': sessionId,
        'deviceId': deviceId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
        'userAgent': userAgent,
        'ipAddress': ipAddress,
        'current': current,
      };
}

final class PasswordChangeResultDto {
  const PasswordChangeResultDto({
    required this.passwordChangedAt,
    required this.revokedDeviceSessionCount,
    required this.reauthenticationRequired,
  });

  factory PasswordChangeResultDto.fromJson(Object? json) {
    final object = _object(json, 'passwordChangeResult');
    return PasswordChangeResultDto(
      passwordChangedAt: _dateTime(object, 'passwordChangedAt'),
      revokedDeviceSessionCount: _integer(object, 'revokedDeviceSessionCount'),
      reauthenticationRequired: _boolean(object, 'reauthenticationRequired'),
    );
  }

  final DateTime passwordChangedAt;
  final int revokedDeviceSessionCount;
  final bool reauthenticationRequired;

  AccountJsonObject toJson() => {
        'passwordChangedAt': passwordChangedAt.toUtc().toIso8601String(),
        'revokedDeviceSessionCount': revokedDeviceSessionCount,
        'reauthenticationRequired': reauthenticationRequired,
      };
}

AccountJsonObject _object(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      // Report a stable protocol error below.
    }
  }
  throw FormatException('$field must be a JSON object');
}

String _string(AccountJsonObject object, String field) {
  final value = object[field];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string');
}

String? _nullableString(AccountJsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$field must be a string or null');
}

int _integer(AccountJsonObject object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw FormatException('$field must be an integer');
}

bool _boolean(AccountJsonObject object, String field) {
  final value = object[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

DateTime _dateTime(AccountJsonObject object, String field) {
  final value = _string(object, field);
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toUtc();
  throw FormatException('$field must be an ISO-8601 timestamp');
}

DateTime? _nullableDateTime(AccountJsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be an ISO-8601 timestamp or null');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toUtc();
  throw FormatException('$field must be an ISO-8601 timestamp or null');
}
