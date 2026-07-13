typedef JsonObject = Map<String, Object?>;

enum SessionRole {
  owner,
  editor,
  viewer;

  static SessionRole fromJson(Object? value, String field) => switch (value) {
        'owner' => SessionRole.owner,
        'editor' => SessionRole.editor,
        'viewer' => SessionRole.viewer,
        _ => throw FormatException('$field must be owner, editor, or viewer'),
      };

  String toJson() => name;
}

enum InviteRole {
  editor,
  viewer;

  static InviteRole fromJson(Object? value, String field) => switch (value) {
        'editor' => InviteRole.editor,
        'viewer' => InviteRole.viewer,
        _ => throw FormatException('$field must be editor or viewer'),
      };

  String toJson() => name;
}

final class ServerInfoDto {
  const ServerInfoDto({
    required this.serverInstanceId,
    required this.protocolMin,
    required this.protocolMax,
    required this.features,
    required this.serverTime,
    required this.environment,
  });

  factory ServerInfoDto.fromJson(Object? json) {
    final object = _object(json, 'serverInfo');
    return ServerInfoDto(
      serverInstanceId: _string(object, 'serverInstanceId'),
      protocolMin: _integer(object, 'protocolMin'),
      protocolMax: _integer(object, 'protocolMax'),
      features: List.unmodifiable(
        _list(object, 'features').asMap().entries.map(
            (entry) => _stringValue(entry.value, 'features[${entry.key}]')),
      ),
      serverTime: _dateTime(object, 'serverTime'),
      environment: _string(object, 'environment'),
    );
  }

  final String serverInstanceId;
  final int protocolMin;
  final int protocolMax;
  final List<String> features;
  final DateTime serverTime;
  final String environment;

  JsonObject toJson() => {
        'serverInstanceId': serverInstanceId,
        'protocolMin': protocolMin,
        'protocolMax': protocolMax,
        'features': features,
        'serverTime': serverTime.toUtc().toIso8601String(),
        'environment': environment,
      };
}

final class ApiUserDto {
  const ApiUserDto({
    required this.id,
    required this.username,
    required this.role,
  });

  factory ApiUserDto.fromJson(Object? json) {
    final object = _object(json, 'user');
    return ApiUserDto(
      id: _string(object, 'id'),
      username: _string(object, 'username'),
      role: _string(object, 'role'),
    );
  }

  final String id;
  final String username;
  final String role;

  JsonObject toJson() => {
        'id': id,
        'username': username,
        'role': role,
      };
}

final class AuthCredentialsDto {
  const AuthCredentialsDto({
    required this.username,
    required this.password,
    this.deviceId,
  });

  final String username;
  final String password;
  final String? deviceId;

  JsonObject toJson() => {
        'username': username,
        'password': password,
        if (deviceId != null) 'deviceId': deviceId,
      };
}

final class AuthSessionDto {
  const AuthSessionDto({
    required this.accessToken,
    required this.accessTokenExpiresIn,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.user,
  });

  factory AuthSessionDto.fromJson(Object? json) {
    final object = _object(json, 'authSession');
    return AuthSessionDto(
      accessToken: _string(object, 'accessToken'),
      accessTokenExpiresIn: _integer(object, 'accessTokenExpiresIn'),
      refreshToken: _string(object, 'refreshToken'),
      refreshTokenExpiresAt: _dateTime(object, 'refreshTokenExpiresAt'),
      user: ApiUserDto.fromJson(object['user']),
    );
  }

  final String accessToken;
  final int accessTokenExpiresIn;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final ApiUserDto user;

  JsonObject toJson() => {
        'accessToken': accessToken,
        'accessTokenExpiresIn': accessTokenExpiresIn,
        'refreshToken': refreshToken,
        'refreshTokenExpiresAt':
            refreshTokenExpiresAt.toUtc().toIso8601String(),
        'user': user.toJson(),
      };
}

final class CollaborationSessionDto {
  const CollaborationSessionDto({
    required this.sessionId,
    required this.title,
    required this.status,
    required this.version,
    required this.role,
    required this.highWatermarkSeq,
    required this.createdAt,
    required this.updatedAt,
    required this.closedAt,
    required this.deletedAt,
  });

  factory CollaborationSessionDto.fromJson(Object? json) {
    final object = _object(json, 'session');
    return CollaborationSessionDto(
      sessionId: _string(object, 'sessionId'),
      title: _string(object, 'title'),
      status: _string(object, 'status'),
      version: _integer(object, 'version'),
      role: SessionRole.fromJson(object['role'], 'role'),
      highWatermarkSeq: _integer(object, 'highWatermarkSeq'),
      createdAt: _dateTime(object, 'createdAt'),
      updatedAt: _dateTime(object, 'updatedAt'),
      closedAt: _nullableDateTime(object, 'closedAt'),
      deletedAt: _nullableDateTime(object, 'deletedAt'),
    );
  }

  final String sessionId;
  final String title;
  final String status;
  final int version;
  final SessionRole role;
  final int highWatermarkSeq;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final DateTime? deletedAt;

  JsonObject toJson() => {
        'sessionId': sessionId,
        'title': title,
        'status': status,
        'version': version,
        'role': role.toJson(),
        'highWatermarkSeq': highWatermarkSeq,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'closedAt': closedAt?.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };
}

final class BootstrapLogDto {
  const BootstrapLogDto({
    required this.syncId,
    required this.time,
    required this.controller,
    required this.callsign,
    this.rstSent,
    this.rstRcvd,
    this.qth,
    this.device,
    this.power,
    this.antenna,
    this.height,
    this.remarks,
  });

  factory BootstrapLogDto.fromJson(Object? json) {
    final object = _object(json, 'bootstrapLog');
    return BootstrapLogDto(
      syncId: _string(object, 'syncId'),
      time: _dateTime(object, 'time'),
      controller: _string(object, 'controller'),
      callsign: _string(object, 'callsign'),
      rstSent: _nullableString(object, 'rstSent'),
      rstRcvd: _nullableString(object, 'rstRcvd'),
      qth: _nullableString(object, 'qth'),
      device: _nullableString(object, 'device'),
      power: _nullableString(object, 'power'),
      antenna: _nullableString(object, 'antenna'),
      height: _nullableString(object, 'height'),
      remarks: _nullableString(object, 'remarks'),
    );
  }

  final String syncId;
  final DateTime time;
  final String controller;
  final String callsign;
  final String? rstSent;
  final String? rstRcvd;
  final String? qth;
  final String? device;
  final String? power;
  final String? antenna;
  final String? height;
  final String? remarks;

  JsonObject toJson() => {
        'syncId': syncId,
        'time': time.toUtc().toIso8601String(),
        'controller': controller,
        'callsign': callsign,
        'rstSent': rstSent,
        'rstRcvd': rstRcvd,
        'qth': qth,
        'device': device,
        'power': power,
        'antenna': antenna,
        'height': height,
        'remarks': remarks,
      };
}

final class CollaborationLogDto {
  const CollaborationLogDto({
    required this.syncId,
    required this.sessionId,
    required this.version,
    required this.time,
    required this.controller,
    required this.callsign,
    required this.rstSent,
    required this.rstRcvd,
    required this.qth,
    required this.device,
    required this.power,
    required this.antenna,
    required this.height,
    required this.remarks,
    this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory CollaborationLogDto.fromJson(Object? json) {
    final object = _object(json, 'log');
    return CollaborationLogDto(
      syncId: _string(object, 'syncId'),
      sessionId: _string(object, 'sessionId'),
      version: _integer(object, 'version'),
      time: _dateTime(object, 'time'),
      controller: _string(object, 'controller'),
      callsign: _string(object, 'callsign'),
      rstSent: _nullableString(object, 'rstSent'),
      rstRcvd: _nullableString(object, 'rstRcvd'),
      qth: _nullableString(object, 'qth'),
      device: _nullableString(object, 'device'),
      power: _nullableString(object, 'power'),
      antenna: _nullableString(object, 'antenna'),
      height: _nullableString(object, 'height'),
      remarks: _nullableString(object, 'remarks'),
      createdBy: object.containsKey('createdBy')
          ? _nullableString(object, 'createdBy')
          : null,
      updatedBy: object.containsKey('updatedBy')
          ? _nullableString(object, 'updatedBy')
          : null,
      createdAt: _dateTime(object, 'createdAt'),
      updatedAt: _dateTime(object, 'updatedAt'),
      deletedAt: _nullableDateTime(object, 'deletedAt'),
    );
  }

  final String syncId;
  final String sessionId;
  final int version;
  final DateTime time;
  final String controller;
  final String callsign;
  final String? rstSent;
  final String? rstRcvd;
  final String? qth;
  final String? device;
  final String? power;
  final String? antenna;
  final String? height;
  final String? remarks;
  final String? createdBy;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  JsonObject toJson() => {
        'syncId': syncId,
        'sessionId': sessionId,
        'version': version,
        'time': time.toUtc().toIso8601String(),
        'controller': controller,
        'callsign': callsign,
        'rstSent': rstSent,
        'rstRcvd': rstRcvd,
        'qth': qth,
        'device': device,
        'power': power,
        'antenna': antenna,
        'height': height,
        'remarks': remarks,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };
}

final class BootstrapLogsResultDto {
  const BootstrapLogsResultDto({
    required this.accepted,
    required this.inserted,
    required this.existing,
    required this.totalLogCount,
  });

  factory BootstrapLogsResultDto.fromJson(Object? json) {
    final object = _object(json, 'bootstrapLogsResult');
    return BootstrapLogsResultDto(
      accepted: _integer(object, 'accepted'),
      inserted: _integer(object, 'inserted'),
      existing: _integer(object, 'existing'),
      totalLogCount: _integer(object, 'totalLogCount'),
    );
  }

  final int accepted;
  final int inserted;
  final int existing;
  final int totalLogCount;

  JsonObject toJson() => {
        'accepted': accepted,
        'inserted': inserted,
        'existing': existing,
        'totalLogCount': totalLogCount,
      };
}

final class ActivateSessionResultDto {
  const ActivateSessionResultDto({
    required this.session,
    required this.highWatermarkSeq,
    required this.logCount,
  });

  factory ActivateSessionResultDto.fromJson(Object? json) {
    final object = _object(json, 'activateSessionResult');
    return ActivateSessionResultDto(
      session: CollaborationSessionDto.fromJson(object['session']),
      highWatermarkSeq: _integer(object, 'highWatermarkSeq'),
      logCount: _integer(object, 'logCount'),
    );
  }

  final CollaborationSessionDto session;
  final int highWatermarkSeq;
  final int logCount;

  JsonObject toJson() => {
        'session': session.toJson(),
        'highWatermarkSeq': highWatermarkSeq,
        'logCount': logCount,
      };
}

final class SessionSnapshotDto {
  const SessionSnapshotDto({
    required this.protocolVersion,
    required this.session,
    required this.highWatermarkSeq,
    required this.includesDeletedLogs,
    required this.logs,
  });

  factory SessionSnapshotDto.fromJson(Object? json) {
    final object = _object(json, 'sessionSnapshot');
    return SessionSnapshotDto(
      protocolVersion: _integer(object, 'protocolVersion'),
      session: CollaborationSessionDto.fromJson(object['session']),
      highWatermarkSeq: _integer(object, 'highWatermarkSeq'),
      // Stage 1 servers predate tombstone-aware snapshot reinstall. Their
      // ordinary publish/first-join snapshots remain valid, while the resync
      // coordinator still explicitly requires this value to be true.
      includesDeletedLogs: object.containsKey('includesDeletedLogs')
          ? _boolean(object, 'includesDeletedLogs')
          : false,
      logs: List.unmodifiable(
        _list(object, 'logs').map(CollaborationLogDto.fromJson),
      ),
    );
  }

  final int protocolVersion;
  final CollaborationSessionDto session;
  final int highWatermarkSeq;
  final bool includesDeletedLogs;
  final List<CollaborationLogDto> logs;

  JsonObject toJson() => {
        'protocolVersion': protocolVersion,
        'session': session.toJson(),
        'highWatermarkSeq': highWatermarkSeq,
        'includesDeletedLogs': includesDeletedLogs,
        'logs': logs.map((log) => log.toJson()).toList(),
      };
}

final class MembershipDto {
  const MembershipDto({
    required this.membershipId,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.version,
    required this.joinedAt,
    required this.updatedAt,
    required this.removedAt,
    this.username,
  });

  factory MembershipDto.fromJson(Object? json) {
    final object = _object(json, 'membership');
    return MembershipDto(
      membershipId: _string(object, 'membershipId'),
      sessionId: _string(object, 'sessionId'),
      userId: _string(object, 'userId'),
      role: SessionRole.fromJson(object['role'], 'role'),
      version: _integer(object, 'version'),
      joinedAt: _dateTime(object, 'joinedAt'),
      updatedAt: _dateTime(object, 'updatedAt'),
      removedAt: _nullableDateTime(object, 'removedAt'),
      username: _nullableString(object, 'username', missingIsNull: true),
    );
  }

  final String membershipId;
  final String sessionId;
  final String userId;
  final SessionRole role;
  final int version;
  final DateTime joinedAt;
  final DateTime updatedAt;
  final DateTime? removedAt;
  final String? username;

  JsonObject toJson() => {
        'membershipId': membershipId,
        'sessionId': sessionId,
        'userId': userId,
        'role': role.toJson(),
        'version': version,
        'joinedAt': joinedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'removedAt': removedAt?.toUtc().toIso8601String(),
        if (username != null) 'username': username,
      };
}

final class CollaborationInviteDto {
  const CollaborationInviteDto({
    required this.inviteId,
    required this.sessionId,
    required this.codeHint,
    required this.role,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.createdBy,
    required this.createdAt,
    required this.revokedAt,
    required this.revokedBy,
    this.code,
    this.linkToken,
  });

  factory CollaborationInviteDto.fromJson(Object? json) {
    final object = _object(json, 'invite');
    return CollaborationInviteDto(
      inviteId: _string(object, 'inviteId'),
      sessionId: _string(object, 'sessionId'),
      codeHint: _string(object, 'codeHint'),
      role: InviteRole.fromJson(object['role'], 'role'),
      maxUses: _integer(object, 'maxUses'),
      usedCount: _integer(object, 'usedCount'),
      expiresAt: _dateTime(object, 'expiresAt'),
      createdBy: _string(object, 'createdBy'),
      createdAt: _dateTime(object, 'createdAt'),
      revokedAt: _nullableDateTime(object, 'revokedAt'),
      revokedBy: _nullableString(object, 'revokedBy'),
      code: _nullableString(object, 'code', missingIsNull: true),
      linkToken: _nullableString(object, 'linkToken', missingIsNull: true),
    );
  }

  final String inviteId;
  final String sessionId;
  final String codeHint;
  final InviteRole role;
  final int maxUses;
  final int usedCount;
  final DateTime expiresAt;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final String? revokedBy;
  final String? code;
  final String? linkToken;

  JsonObject toJson() => {
        'inviteId': inviteId,
        'sessionId': sessionId,
        'codeHint': codeHint,
        'role': role.toJson(),
        'maxUses': maxUses,
        'usedCount': usedCount,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
        'revokedBy': revokedBy,
        if (code != null) 'code': code,
        if (linkToken != null) 'linkToken': linkToken,
      };
}

final class CreateInviteRequestDto {
  const CreateInviteRequestDto({
    required this.role,
    this.expiresInHours = 24,
    this.maxUses = 1,
    this.includeLinkToken = false,
  });

  final InviteRole role;
  final int expiresInHours;
  final int maxUses;
  final bool includeLinkToken;

  JsonObject toJson() => {
        'role': role.toJson(),
        'expiresInHours': expiresInHours,
        'maxUses': maxUses,
        'includeLinkToken': includeLinkToken,
      };
}

final class RedeemInviteRequestDto {
  RedeemInviteRequestDto({
    this.code,
    this.linkToken,
    required this.joinRequestId,
    this.deviceId,
  }) {
    if ((code == null) == (linkToken == null)) {
      throw ArgumentError('Provide exactly one of code or linkToken');
    }
  }

  final String? code;
  final String? linkToken;
  final String joinRequestId;
  final String? deviceId;

  JsonObject toJson() => {
        if (code != null) 'code': code,
        if (linkToken != null) 'linkToken': linkToken,
        'joinRequestId': joinRequestId,
        if (deviceId != null) 'deviceId': deviceId,
      };
}

final class RedeemInviteResultDto {
  const RedeemInviteResultDto({
    required this.membership,
    required this.roleGranted,
    required this.session,
    required this.highWatermarkSeq,
  });

  factory RedeemInviteResultDto.fromJson(Object? json) {
    final object = _object(json, 'redeemInviteResult');
    return RedeemInviteResultDto(
      membership: MembershipDto.fromJson(object['membership']),
      roleGranted: InviteRole.fromJson(object['roleGranted'], 'roleGranted'),
      session: CollaborationSessionDto.fromJson(object['session']),
      highWatermarkSeq: _integer(object, 'highWatermarkSeq'),
    );
  }

  final MembershipDto membership;
  final InviteRole roleGranted;
  final CollaborationSessionDto session;
  final int highWatermarkSeq;

  JsonObject toJson() => {
        'membership': membership.toJson(),
        'roleGranted': roleGranted.toJson(),
        'session': session.toJson(),
        'highWatermarkSeq': highWatermarkSeq,
      };
}

final class OwnershipTransferDto {
  const OwnershipTransferDto({
    required this.sessionId,
    required this.previousOwner,
    required this.owner,
  });

  factory OwnershipTransferDto.fromJson(Object? json) {
    final object = _object(json, 'ownershipTransfer');
    return OwnershipTransferDto(
      sessionId: _string(object, 'sessionId'),
      previousOwner: MembershipDto.fromJson(object['previousOwner']),
      owner: MembershipDto.fromJson(object['owner']),
    );
  }

  final String sessionId;
  final MembershipDto previousOwner;
  final MembershipDto owner;

  JsonObject toJson() => {
        'sessionId': sessionId,
        'previousOwner': previousOwner.toJson(),
        'owner': owner.toJson(),
      };
}

final class RemovedMemberDto {
  const RemovedMemberDto({
    required this.removed,
    required this.sessionId,
    required this.userId,
    required this.removedAt,
  });

  factory RemovedMemberDto.fromJson(Object? json) {
    final object = _object(json, 'removedMember');
    return RemovedMemberDto(
      removed: _boolean(object, 'removed'),
      sessionId: _string(object, 'sessionId'),
      userId: _string(object, 'userId'),
      removedAt: _dateTime(object, 'removedAt'),
    );
  }

  final bool removed;
  final String sessionId;
  final String userId;
  final DateTime removedAt;

  JsonObject toJson() => {
        'removed': removed,
        'sessionId': sessionId,
        'userId': userId,
        'removedAt': removedAt.toUtc().toIso8601String(),
      };
}

final class LeaveSessionResultDto {
  const LeaveSessionResultDto({
    required this.left,
    required this.membership,
  });

  factory LeaveSessionResultDto.fromJson(Object? json) {
    final object = _object(json, 'leaveSessionResult');
    return LeaveSessionResultDto(
      left: _boolean(object, 'left'),
      membership: MembershipDto.fromJson(object['membership']),
    );
  }

  final bool left;
  final MembershipDto membership;
}

final class PublicShareDto {
  const PublicShareDto({
    required this.publicShareId,
    required this.sessionId,
    required this.expiresAt,
    required this.createdBy,
    required this.createdAt,
    required this.revokedAt,
    required this.revokedBy,
    this.secret,
  });

  factory PublicShareDto.fromJson(Object? json) {
    final object = _object(json, 'publicShare');
    return PublicShareDto(
      publicShareId: _string(object, 'publicShareId'),
      sessionId: _string(object, 'sessionId'),
      expiresAt: _dateTime(object, 'expiresAt'),
      createdBy: _string(object, 'createdBy'),
      createdAt: _dateTime(object, 'createdAt'),
      revokedAt: _nullableDateTime(object, 'revokedAt'),
      revokedBy: _nullableString(object, 'revokedBy'),
      secret: _nullableString(object, 'secret', missingIsNull: true),
    );
  }

  final String publicShareId;
  final String sessionId;
  final DateTime expiresAt;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final String? revokedBy;
  final String? secret;

  bool get active => revokedAt == null && expiresAt.isAfter(DateTime.now());

  JsonObject toJson() => {
        'publicShareId': publicShareId,
        'sessionId': sessionId,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
        'revokedBy': revokedBy,
        if (secret != null) 'secret': secret,
      };
}

final class PublicSharePageDto {
  const PublicSharePageDto({
    required this.publicShares,
    required this.nextCursor,
  });

  factory PublicSharePageDto.fromJson(Object? json) {
    final object = _object(json, 'publicSharePage');
    return PublicSharePageDto(
      publicShares: List.unmodifiable(
        _list(object, 'publicShares').map(PublicShareDto.fromJson),
      ),
      nextCursor: _nullableString(object, 'nextCursor'),
    );
  }

  final List<PublicShareDto> publicShares;
  final String? nextCursor;
}

/// Canonical collaboration event shared by mutation responses, event catch-up
/// and WebSocket notifications.
final class CollaborationEventDto {
  const CollaborationEventDto({
    required this.protocolVersion,
    required this.eventId,
    required this.sessionId,
    required this.seq,
    required this.type,
    required this.entityType,
    required this.entityId,
    required this.entityVersion,
    required this.occurredAt,
    required this.payload,
    this.mutationId,
    this.actor,
  });

  factory CollaborationEventDto.fromJson(Object? json) {
    final object = _object(json, 'event');
    return CollaborationEventDto(
      protocolVersion: _integer(object, 'protocolVersion'),
      eventId: _string(object, 'eventId'),
      sessionId: _string(object, 'sessionId'),
      seq: _integer(object, 'seq'),
      type: _string(object, 'type'),
      entityType: _string(object, 'entityType'),
      entityId: _string(object, 'entityId'),
      entityVersion: _integer(object, 'entityVersion'),
      mutationId: _nullableString(
        object,
        'mutationId',
        missingIsNull: true,
      ),
      actor: object['actor'] == null ? null : _object(object['actor'], 'actor'),
      occurredAt: _dateTime(object, 'occurredAt'),
      payload: _object(object['payload'], 'payload'),
    );
  }

  final int protocolVersion;
  final String eventId;
  final String sessionId;
  final int seq;
  final String type;
  final String entityType;
  final String entityId;
  final int entityVersion;
  final String? mutationId;
  final JsonObject? actor;
  final DateTime occurredAt;
  final JsonObject payload;

  JsonObject toJson() => {
        'protocolVersion': protocolVersion,
        'eventId': eventId,
        'sessionId': sessionId,
        'seq': seq,
        'type': type,
        'entityType': entityType,
        'entityId': entityId,
        'entityVersion': entityVersion,
        'mutationId': mutationId,
        'actor': actor,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'payload': payload,
      };
}

final class SessionEventsPageDto {
  const SessionEventsPageDto({
    required this.afterSeq,
    required this.toSeq,
    required this.headSeq,
    required this.minAvailableSeq,
    required this.hasMore,
    required this.events,
  });

  factory SessionEventsPageDto.fromJson(Object? json) {
    final object = _object(json, 'eventsPage');
    return SessionEventsPageDto(
      afterSeq: _integer(object, 'afterSeq'),
      toSeq: _integer(object, 'toSeq'),
      headSeq: _integer(object, 'headSeq'),
      minAvailableSeq: _integer(object, 'minAvailableSeq'),
      hasMore: _boolean(object, 'hasMore'),
      events: List.unmodifiable(
        _list(object, 'events').map(CollaborationEventDto.fromJson),
      ),
    );
  }

  final int afterSeq;
  final int toSeq;
  final int headSeq;
  final int minAvailableSeq;
  final bool hasMore;
  final List<CollaborationEventDto> events;

  JsonObject toJson() => {
        'afterSeq': afterSeq,
        'toSeq': toSeq,
        'headSeq': headSeq,
        'minAvailableSeq': minAvailableSeq,
        'hasMore': hasMore,
        'events': events.map((event) => event.toJson()).toList(),
      };
}

/// One durable operation read from the Rust outbox.
///
/// Payload fields stay protocol-shaped instead of being converted to UI
/// models, so a retry serializes exactly the same logical mutation.
final class CollaborationMutationDto {
  const CollaborationMutationDto({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.baseVersion,
    this.observedSeq,
    this.queuedAt,
    this.value,
    this.patch,
    this.confirm,
  });

  factory CollaborationMutationDto.fromJson(Object? json) {
    final object = _object(json, 'mutation');
    return CollaborationMutationDto(
      mutationId: _string(object, 'mutationId'),
      entityType: _string(object, 'entityType'),
      entityId: _string(object, 'entityId'),
      operation: _string(object, 'operation'),
      baseVersion: _integer(object, 'baseVersion'),
      observedSeq: object['observedSeq'] == null
          ? null
          : _integer(object, 'observedSeq'),
      queuedAt:
          object['queuedAt'] == null ? null : _dateTime(object, 'queuedAt'),
      value: object['value'] == null
          ? null
          : _object(object['value'], 'mutation.value'),
      patch: object['patch'] == null
          ? null
          : _object(object['patch'], 'mutation.patch'),
      confirm: object['confirm'],
    );
  }

  final String mutationId;
  final String entityType;
  final String entityId;
  final String operation;
  final int baseVersion;
  final int? observedSeq;
  final DateTime? queuedAt;
  final JsonObject? value;
  final JsonObject? patch;
  final Object? confirm;

  JsonObject toJson() => {
        'mutationId': mutationId,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation,
        'baseVersion': baseVersion,
        if (observedSeq != null) 'observedSeq': observedSeq,
        if (value != null) 'value': value,
        if (patch != null) 'patch': patch,
        if (confirm != null) 'confirm': confirm,
        if (queuedAt != null) 'queuedAt': queuedAt!.toUtc().toIso8601String(),
      };
}

final class MutationResultDto {
  const MutationResultDto({
    required this.mutationId,
    required this.status,
    this.event,
    this.code,
    this.message,
    this.currentVersion,
    this.currentEntity,
    this.details,
  });

  factory MutationResultDto.fromJson(Object? json) {
    final object = _object(json, 'mutationResult');
    final rawCurrentVersion = object['currentVersion'];
    if (rawCurrentVersion != null && rawCurrentVersion is! int) {
      throw const FormatException('currentVersion must be an integer or null');
    }
    return MutationResultDto(
      mutationId: _string(object, 'mutationId'),
      status: _string(object, 'status'),
      event: object['event'] == null
          ? null
          : CollaborationEventDto.fromJson(object['event']),
      code: _nullableString(object, 'code', missingIsNull: true),
      message: _nullableString(object, 'message', missingIsNull: true),
      currentVersion: rawCurrentVersion as int?,
      currentEntity: object['currentEntity'] == null
          ? null
          : _object(object['currentEntity'], 'currentEntity'),
      details: object['details'],
    );
  }

  final String mutationId;
  final String status;
  final CollaborationEventDto? event;
  final String? code;
  final String? message;
  final int? currentVersion;
  final JsonObject? currentEntity;
  final Object? details;

  JsonObject toJson() => {
        'mutationId': mutationId,
        'status': status,
        if (event != null) 'event': event!.toJson(),
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (currentVersion != null) 'currentVersion': currentVersion,
        if (currentEntity != null) 'currentEntity': currentEntity,
        if (details != null) 'details': details,
      };
}

final class MutationBatchResultDto {
  const MutationBatchResultDto({
    required this.headSeq,
    required this.results,
  });

  factory MutationBatchResultDto.fromJson(Object? json) {
    final object = _object(json, 'mutationBatchResult');
    return MutationBatchResultDto(
      headSeq: _integer(object, 'headSeq'),
      results: List.unmodifiable(
        _list(object, 'results').map(MutationResultDto.fromJson),
      ),
    );
  }

  final int headSeq;
  final List<MutationResultDto> results;

  JsonObject toJson() => {
        'headSeq': headSeq,
        'results': results.map((result) => result.toJson()).toList(),
      };
}

final class WebSocketTicketDto {
  const WebSocketTicketDto({
    required this.ticket,
    required this.expiresAt,
    required this.sessionId,
    required this.role,
    required this.membershipVersion,
    required this.afterSeq,
  });

  factory WebSocketTicketDto.fromJson(Object? json) {
    final object = _object(json, 'webSocketTicket');
    return WebSocketTicketDto(
      ticket: _string(object, 'ticket'),
      expiresAt: _dateTime(object, 'expiresAt'),
      sessionId: _string(object, 'sessionId'),
      role: SessionRole.fromJson(object['role'], 'role'),
      membershipVersion: _integer(object, 'membershipVersion'),
      afterSeq: _integer(object, 'afterSeq'),
    );
  }

  final String ticket;
  final DateTime expiresAt;
  final String sessionId;
  final SessionRole role;
  final int membershipVersion;
  final int afterSeq;

  JsonObject toJson() => {
        'ticket': ticket,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'sessionId': sessionId,
        'role': role.toJson(),
        'membershipVersion': membershipVersion,
        'afterSeq': afterSeq,
      };
}

final class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    required this.requestId,
    this.details,
  });

  factory ApiErrorDto.fromJson(Object? json) {
    final object = _object(json, 'error');
    return ApiErrorDto(
      code: _string(object, 'code'),
      message: _string(object, 'message'),
      requestId: _string(object, 'requestId'),
      details: object['details'],
    );
  }

  final String code;
  final String message;
  final String requestId;
  final Object? details;

  JsonObject toJson() => {
        'code': code,
        'message': message,
        'requestId': requestId,
        if (details != null) 'details': details,
      };
}

JsonObject _object(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      // Report the protocol field below rather than leaking a cast error.
    }
  }
  throw FormatException('$field must be a JSON object');
}

String _string(JsonObject object, String field) {
  if (!object.containsKey(field)) {
    throw FormatException('$field is required');
  }
  return _stringValue(object[field], field);
}

String _stringValue(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field must be a string');
}

String? _nullableString(
  JsonObject object,
  String field, {
  bool missingIsNull = false,
}) {
  if (!object.containsKey(field)) {
    if (missingIsNull) return null;
    throw FormatException('$field is required');
  }
  final value = object[field];
  if (value == null) return null;
  return _stringValue(value, field);
}

int _integer(JsonObject object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw FormatException('$field must be an integer');
}

bool _boolean(JsonObject object, String field) {
  final value = object[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

List<Object?> _list(JsonObject object, String field) {
  final value = object[field];
  if (value is List) return List<Object?>.from(value);
  throw FormatException('$field must be a JSON array');
}

DateTime _dateTime(JsonObject object, String field) {
  final value = _string(object, field);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field must be an RFC 3339 timestamp');
  }
  return parsed;
}

DateTime? _nullableDateTime(JsonObject object, String field) {
  final value = _nullableString(object, field);
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field must be an RFC 3339 timestamp');
  }
  return parsed;
}
