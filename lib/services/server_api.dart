import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/live_draft.dart';

/// Persistence boundary for authentication state.
///
/// The protocol layer intentionally does not choose a storage plugin. Callers can
/// provide a secure persistent implementation; tests can use [MemoryTokenStore].
abstract interface class TokenStore {
  Future<AuthSessionDto?> read();

  Future<void> write(AuthSessionDto session);

  Future<void> clear();
}

final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._session]);

  AuthSessionDto? _session;

  @override
  Future<AuthSessionDto?> read() async => _session;

  @override
  Future<void> write(AuthSessionDto session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

final class ServerApiException implements Exception {
  const ServerApiException({
    required this.error,
    required this.statusCode,
    required this.retryable,
    this.cause,
  });

  final ApiErrorDto error;
  final int? statusCode;
  final bool retryable;
  final Object? cause;

  String get code => error.code;
  String get message => error.message;
  String get requestId => error.requestId;
  Object? get details => error.details;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'ServerApiException$status: ${error.code}: ${error.message}';
  }
}

final class ServerApi {
  ServerApi({
    required Uri baseUri,
    required this.tokenStore,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.deviceId,
    this.onAuthInvalidated,
  })  : _apiBaseUri = _normalizeApiBaseUri(baseUri),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  final TokenStore tokenStore;
  final Duration timeout;
  final String? deviceId;
  final void Function()? onAuthInvalidated;
  final Uri _apiBaseUri;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  final Map<String, Future<AuthSessionDto>> _refreshesInFlight = {};

  Future<ServerInfoDto> getServerInfo() async {
    final response = await _publicRequest('GET', '/server-info');
    return _parseResponse(response, ServerInfoDto.fromJson);
  }

  Future<AuthSessionDto> register(AuthCredentialsDto credentials) async {
    final response = await _publicRequest(
      'POST',
      '/auth/register',
      body: credentials.toJson(),
    );
    final session = _parseResponse(response, AuthSessionDto.fromJson);
    await tokenStore.write(session);
    return session;
  }

  Future<AuthSessionDto> login(AuthCredentialsDto credentials) async {
    final response = await _publicRequest(
      'POST',
      '/auth/login',
      body: credentials.toJson(),
    );
    final session = _parseResponse(response, AuthSessionDto.fromJson);
    await tokenStore.write(session);
    return session;
  }

  Future<AuthSessionDto> refresh({String? deviceId}) async {
    final current = await _requireSession();
    return _refreshOnce(current.refreshToken, deviceId: deviceId);
  }

  Future<void> logout() async {
    final response = await _authorizedRequest(
      'POST',
      '/auth/logout',
      bodyForSession: (session) => {'refreshToken': session.refreshToken},
    );
    _expectEmpty(response);
    await tokenStore.clear();
  }

  Future<ApiUserDto> getMe() async {
    final response = await _authorizedRequest('GET', '/auth/me');
    return _parseResponse(response, ApiUserDto.fromJson);
  }

  Future<List<CollaborationSessionDto>> listSessions() async {
    final response = await _authorizedRequest('GET', '/sessions');
    return _parseResponse(response, (json) {
      final values = _jsonArray(json, 'sessions');
      return List.unmodifiable(values.map(CollaborationSessionDto.fromJson));
    });
  }

  Future<CollaborationSessionDto> putSession({
    required String sessionId,
    required String title,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'PUT',
      '/sessions/${_segment(sessionId)}',
      body: {'title': title},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => CollaborationSessionDto.fromJson(
        _jsonObject(json, 'putSessionResult')['session'],
      ),
    );
  }

  Future<BootstrapLogsResultDto> bootstrapLogs({
    required String sessionId,
    required List<BootstrapLogDto> items,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/bootstrap/logs',
      body: {'items': items.map((item) => item.toJson()).toList()},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, BootstrapLogsResultDto.fromJson);
  }

  Future<ActivateSessionResultDto> activateSession({
    required String sessionId,
    required int expectedLogCount,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/activate',
      body: {'expectedLogCount': expectedLogCount},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, ActivateSessionResultDto.fromJson);
  }

  Future<SessionSnapshotDto> getSessionSnapshot(
    String sessionId, {
    bool includeDeleted = false,
  }) async {
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/snapshot',
      queryParameters: includeDeleted ? {'includeDeleted': 'true'} : null,
    );
    return _parseResponse(response, SessionSnapshotDto.fromJson);
  }

  Future<SessionEventsPageDto> getSessionEvents({
    required String sessionId,
    required int afterSeq,
    int limit = 500,
  }) async {
    if (afterSeq < 0) {
      throw ArgumentError.value(afterSeq, 'afterSeq', 'must not be negative');
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/events',
      queryParameters: {
        'afterSeq': '$afterSeq',
        'limit': '$limit',
      },
    );
    return _parseResponse(response, SessionEventsPageDto.fromJson);
  }

  Future<MutationBatchResultDto> submitMutations({
    required String sessionId,
    required String deviceId,
    required List<CollaborationMutationDto> operations,
  }) async {
    if (operations.isEmpty || operations.length > 100) {
      throw ArgumentError.value(
        operations.length,
        'operations',
        'must contain between 1 and 100 mutations',
      );
    }
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/mutations',
      body: {
        'protocolVersion': 1,
        'deviceId': deviceId,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
      },
    );
    return _parseResponse(response, MutationBatchResultDto.fromJson);
  }

  Future<WebSocketTicketDto> createCollaborationWebSocketTicket({
    required String sessionId,
    required String deviceId,
    required int afterSeq,
  }) async {
    if (afterSeq < 0) {
      throw ArgumentError.value(afterSeq, 'afterSeq', 'must not be negative');
    }
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/ws-ticket',
      body: {
        'deviceId': deviceId,
        'afterSeq': afterSeq,
      },
    );
    return _parseResponse(response, WebSocketTicketDto.fromJson);
  }

  Uri collaborationWebSocketUri(String ticket) {
    final normalized = ticket.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(ticket, 'ticket', 'must not be empty');
    }
    const apiSuffix = '/api/v1';
    final apiPath = _apiBaseUri.path;
    final rootPath = apiPath.endsWith(apiSuffix)
        ? apiPath.substring(0, apiPath.length - apiSuffix.length)
        : '';
    return _apiBaseUri.replace(
      scheme: _apiBaseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '$rootPath/ws/collaboration',
      queryParameters: {'ticket': normalized},
      fragment: null,
    );
  }

  Future<MembershipDto> getMembership(String sessionId) async {
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/membership',
    );
    return _parseResponse(
      response,
      (json) => MembershipDto.fromJson(
        _jsonObject(json, 'membershipResult')['membership'],
      ),
    );
  }

  Future<LeaveSessionResultDto> leaveSession({
    required String sessionId,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/membership',
      body: const <String, Object?>{},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, LeaveSessionResultDto.fromJson);
  }

  Future<LiveDraftSnapshotDto> getLiveDraft(String sessionId) async {
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/live-draft',
    );
    return _parseResponse(response, LiveDraftSnapshotDto.fromJson);
  }

  Future<LiveDraftLockDto> acquireLiveDraftLock({
    required String sessionId,
    required String field,
    required String deviceId,
  }) async {
    if (!liveDraftFieldNames.contains(field)) {
      throw ArgumentError.value(field, 'field', 'unknown live draft field');
    }
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/live-draft/locks',
      body: {'field': field, 'deviceId': deviceId},
    );
    final lock = _parseResponse(
      response,
      (json) => LiveDraftLockDto.fromJson(
        _jsonObject(json, 'liveDraftLockResult')['lock'],
      ),
    );
    if (lock.sessionId != sessionId) {
      throw _clientException(
        code: 'INVALID_RESPONSE',
        message: 'The live draft lock belongs to another Session',
        statusCode: response.statusCode,
      );
    }
    return lock;
  }

  Future<LiveDraftLockDto> renewLiveDraftLock({
    required String sessionId,
    required String leaseId,
    required String deviceId,
  }) async {
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/live-draft/locks/'
          '${_segment(leaseId)}/renew',
      body: {'deviceId': deviceId},
    );
    final lock = _parseResponse(
      response,
      (json) => LiveDraftLockDto.fromJson(
        _jsonObject(json, 'liveDraftLockRenewResult')['lock'],
      ),
    );
    if (lock.sessionId != sessionId || lock.leaseId != leaseId) {
      throw _clientException(
        code: 'INVALID_RESPONSE',
        message: 'The renewed live draft lock does not match the request',
        statusCode: response.statusCode,
      );
    }
    return lock;
  }

  Future<void> releaseLiveDraftLock({
    required String sessionId,
    required String leaseId,
    required String deviceId,
  }) async {
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/live-draft/locks/'
          '${_segment(leaseId)}',
      body: {'deviceId': deviceId},
    );
    _parseResponse(response, (json) {
      final result = _jsonObject(json, 'liveDraftLockReleaseResult');
      if (result['released'] != true) {
        throw const FormatException('released must be true');
      }
    });
  }

  Future<LiveDraftPatchResultDto> updateLiveDraft({
    required String sessionId,
    required String deviceId,
    required int clientSeq,
    required List<LiveDraftPatchUpdateDto> updates,
  }) async {
    if (clientSeq < 1) {
      throw ArgumentError.value(clientSeq, 'clientSeq', 'must be positive');
    }
    if (updates.isEmpty) {
      throw ArgumentError.value(updates, 'updates', 'must not be empty');
    }
    if (updates.length > liveDraftFieldNames.length) {
      throw ArgumentError.value(updates, 'updates', 'contains too many fields');
    }
    final fields = <String>{};
    if (updates.any((update) => !fields.add(update.field))) {
      throw ArgumentError.value(
          updates, 'updates', 'contains duplicate fields');
    }
    final response = await _authorizedRequest(
      'PATCH',
      '/sessions/${_segment(sessionId)}/live-draft',
      body: {
        'deviceId': deviceId,
        'clientSeq': clientSeq,
        'updates': updates.map((update) => update.toJson()).toList(),
      },
    );
    return _parseResponse(response, LiveDraftPatchResultDto.fromJson);
  }

  Future<LiveDraftCommitResultDto> commitLiveDraft({
    required String sessionId,
    required String deviceId,
    required int expectedDraftVersion,
    required String syncId,
    required String idempotencyKey,
  }) async {
    if (expectedDraftVersion < 1) {
      throw ArgumentError.value(
        expectedDraftVersion,
        'expectedDraftVersion',
        'must be positive',
      );
    }
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/live-draft/commit',
      body: {
        'deviceId': deviceId,
        'expectedDraftVersion': expectedDraftVersion,
        'syncId': syncId,
      },
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, LiveDraftCommitResultDto.fromJson);
  }

  Future<LiveDraftDiscardResultDto> discardLiveDraft({
    required String sessionId,
    required String deviceId,
    required int expectedDraftVersion,
    required String idempotencyKey,
  }) async {
    if (expectedDraftVersion < 1) {
      throw ArgumentError.value(
        expectedDraftVersion,
        'expectedDraftVersion',
        'must be positive',
      );
    }
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/live-draft',
      body: {
        'deviceId': deviceId,
        'expectedDraftVersion': expectedDraftVersion,
      },
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, LiveDraftDiscardResultDto.fromJson);
  }

  Future<List<MembershipDto>> listMembers(String sessionId) async {
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/members',
    );
    return _parseResponse(response, (json) {
      final object = _jsonObject(json, 'membersResult');
      final values = _jsonArray(object['members'], 'members');
      return List.unmodifiable(values.map(MembershipDto.fromJson));
    });
  }

  Future<MembershipDto> updateMemberRole({
    required String sessionId,
    required String userId,
    required InviteRole role,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'PATCH',
      '/sessions/${_segment(sessionId)}/members/${_segment(userId)}',
      body: {'role': role.toJson()},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => MembershipDto.fromJson(
        _jsonObject(json, 'updateMemberResult')['membership'],
      ),
    );
  }

  Future<RemovedMemberDto> removeMember({
    required String sessionId,
    required String userId,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/members/${_segment(userId)}',
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, RemovedMemberDto.fromJson);
  }

  Future<OwnershipTransferDto> transferOwnership({
    required String sessionId,
    required String newOwnerUserId,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/transfer-ownership',
      body: {'newOwnerUserId': newOwnerUserId},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(response, OwnershipTransferDto.fromJson);
  }

  Future<CollaborationInviteDto> createInvite({
    required String sessionId,
    required CreateInviteRequestDto request,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/invites',
      body: request.toJson(),
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => CollaborationInviteDto.fromJson(
        _jsonObject(json, 'createInviteResult')['invite'],
      ),
    );
  }

  Future<List<CollaborationInviteDto>> listInvites(String sessionId) async {
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/invites',
    );
    return _parseResponse(response, (json) {
      final object = _jsonObject(json, 'invitesResult');
      final values = _jsonArray(object['invites'], 'invites');
      return List.unmodifiable(values.map(CollaborationInviteDto.fromJson));
    });
  }

  Future<CollaborationInviteDto> revokeInvite({
    required String sessionId,
    required String inviteId,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/invites/${_segment(inviteId)}',
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => CollaborationInviteDto.fromJson(
        _jsonObject(json, 'revokeInviteResult')['invite'],
      ),
    );
  }

  Future<PublicShareDto> createPublicShare({
    required String sessionId,
    required int expiresInHours,
    required String idempotencyKey,
  }) async {
    if (expiresInHours < 1 || expiresInHours > 24 * 30) {
      throw ArgumentError.value(
        expiresInHours,
        'expiresInHours',
        'must be between 1 and 720',
      );
    }
    final response = await _authorizedRequest(
      'POST',
      '/sessions/${_segment(sessionId)}/public-shares',
      body: {'expiresInHours': expiresInHours},
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => PublicShareDto.fromJson(
        _jsonObject(json, 'createPublicShareResult')['publicShare'],
      ),
    );
  }

  Future<PublicSharePageDto> listPublicShares({
    required String sessionId,
    int limit = 50,
    String? after,
  }) async {
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 50');
    }
    if (after != null && after.isEmpty) {
      throw ArgumentError.value(after, 'after', 'must not be empty');
    }
    final response = await _authorizedRequest(
      'GET',
      '/sessions/${_segment(sessionId)}/public-shares',
      queryParameters: {
        'limit': '$limit',
        if (after != null) 'after': after,
      },
    );
    return _parseResponse(response, PublicSharePageDto.fromJson);
  }

  Future<PublicShareDto> revokePublicShare({
    required String sessionId,
    required String publicShareId,
    required String idempotencyKey,
  }) async {
    final response = await _authorizedRequest(
      'DELETE',
      '/sessions/${_segment(sessionId)}/public-shares/'
          '${_segment(publicShareId)}',
      headers: _idempotencyHeaders(idempotencyKey),
    );
    return _parseResponse(
      response,
      (json) => PublicShareDto.fromJson(
        _jsonObject(json, 'revokePublicShareResult')['publicShare'],
      ),
    );
  }

  Uri publicSharePageUri(PublicShareDto share) {
    final secret = share.secret;
    if (secret == null || secret.isEmpty) {
      throw ArgumentError.value(share, 'share', 'secret is required');
    }
    const apiSuffix = '/api/v1';
    final apiPath = _apiBaseUri.path;
    final rootPath = apiPath.endsWith(apiSuffix)
        ? apiPath.substring(0, apiPath.length - apiSuffix.length)
        : '';
    return _apiBaseUri.replace(
      path: '$rootPath/live/${_segment(share.publicShareId)}',
      query: null,
      fragment: secret,
    );
  }

  Future<RedeemInviteResultDto> redeemInvite(
    RedeemInviteRequestDto request,
  ) async {
    final response = await _authorizedRequest(
      'POST',
      '/collaboration-invites/redeem',
      body: request.toJson(),
      headers: _idempotencyHeaders(request.joinRequestId),
    );
    return _parseResponse(response, RedeemInviteResultDto.fromJson);
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<http.Response> _publicRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    final response = await _send(method, path, body: body);
    _throwForError(response);
    return response;
  }

  Future<http.Response> _authorizedRequest(
    String method,
    String path, {
    Object? body,
    Object? Function(AuthSessionDto session)? bodyForSession,
    Map<String, String> headers = const {},
    Map<String, String>? queryParameters,
  }) async {
    final original = await _requireSession();
    var response = await _send(
      method,
      path,
      accessToken: original.accessToken,
      body: bodyForSession?.call(original) ?? body,
      headers: headers,
      queryParameters: queryParameters,
    );
    if (response.statusCode != 401) {
      _throwForError(response);
      return response;
    }

    final latest = await tokenStore.read();
    if (latest == null) {
      onAuthInvalidated?.call();
      throw _authContextChanged();
    }
    if (latest.user.id != original.user.id) {
      throw _authContextChanged();
    }

    final AuthSessionDto replacement;
    if (latest.accessToken != original.accessToken ||
        latest.refreshToken != original.refreshToken) {
      replacement = latest;
    } else {
      replacement = await _refreshOnce(original.refreshToken);
    }
    if (replacement.user.id != original.user.id) {
      throw _authContextChanged();
    }

    response = await _send(
      method,
      path,
      accessToken: replacement.accessToken,
      body: bodyForSession?.call(replacement) ?? body,
      headers: headers,
      queryParameters: queryParameters,
    );
    if (response.statusCode == 401) {
      await _clearIfCurrent(replacement.refreshToken);
    }
    _throwForError(response);
    return response;
  }

  Future<AuthSessionDto> _requireSession() async {
    final session = await tokenStore.read();
    if (session != null) return session;
    throw _clientException(
      code: 'AUTH_REQUIRED',
      message: 'Authentication is required',
    );
  }

  Future<AuthSessionDto> _refreshOnce(
    String refreshToken, {
    String? deviceId,
  }) {
    final existing = _refreshesInFlight[refreshToken];
    if (existing != null) return existing;

    final refresh = _performRefresh(refreshToken, deviceId: deviceId);
    _refreshesInFlight[refreshToken] = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshesInFlight[refreshToken], refresh)) {
        _refreshesInFlight.remove(refreshToken);
      }
    });
  }

  Future<AuthSessionDto> _performRefresh(
    String refreshToken, {
    String? deviceId,
  }) async {
    final resolvedDeviceId = deviceId ?? this.deviceId;
    final response = await _send(
      'POST',
      '/auth/refresh',
      body: {
        'refreshToken': refreshToken,
        if (resolvedDeviceId != null) 'deviceId': resolvedDeviceId,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        await _clearIfCurrent(refreshToken);
      }
      _throwForError(response);
    }
    final session = _parseResponse(response, AuthSessionDto.fromJson);
    final current = await tokenStore.read();
    if (current?.refreshToken == refreshToken) {
      await tokenStore.write(session);
    }
    return session;
  }

  ServerApiException _authContextChanged() => _clientException(
        code: 'AUTH_CONTEXT_CHANGED',
        message: 'Authentication context changed while the request was active',
      );

  Future<void> _clearIfCurrent(String refreshToken) async {
    final current = await tokenStore.read();
    if (current?.refreshToken == refreshToken) {
      await tokenStore.clear();
      onAuthInvalidated?.call();
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String> headers = const {},
    Map<String, String>? queryParameters,
  }) async {
    final request = http.Request(
      method,
      _uri(path, queryParameters: queryParameters),
    );
    request.headers.addAll({
      'Accept': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (deviceId != null) 'X-Device-Id': deviceId!,
      ...headers,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    try {
      return await (() async {
        final streamed = await _httpClient.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(timeout);
    } on TimeoutException catch (error) {
      throw _clientException(
        code: 'NETWORK_TIMEOUT',
        message: 'The server request timed out',
        retryable: true,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw _clientException(
        code: 'NETWORK_ERROR',
        message: 'The server request failed',
        retryable: true,
        cause: error,
      );
    }
  }

  T _parseResponse<T>(http.Response response, T Function(Object? json) parse) {
    try {
      if (response.body.trim().isEmpty) {
        throw const FormatException('response body is empty');
      }
      return parse(jsonDecode(response.body));
    } on FormatException catch (error) {
      throw _clientException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid protocol response',
        statusCode: response.statusCode,
        cause: error,
      );
    }
  }

  void _expectEmpty(http.Response response) {
    if (response.body.trim().isNotEmpty) {
      throw _clientException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an unexpected response body',
        statusCode: response.statusCode,
      );
    }
  }

  void _throwForError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    ApiErrorDto? apiError;
    try {
      final decoded = jsonDecode(response.body);
      final envelope = _jsonObject(decoded, 'errorEnvelope');
      apiError = ApiErrorDto.fromJson(envelope['error']);
    } on FormatException {
      // Fall through to a stable client-side envelope.
    }

    throw ServerApiException(
      error: apiError ??
          ApiErrorDto(
            code: 'HTTP_ERROR',
            message: 'The server returned HTTP ${response.statusCode}',
            requestId: response.headers['x-request-id'] ?? 'unknown',
          ),
      statusCode: response.statusCode,
      retryable: _isRetryableStatus(response.statusCode),
    );
  }

  ServerApiException _clientException({
    required String code,
    required String message,
    int? statusCode,
    bool retryable = false,
    Object? cause,
  }) {
    return ServerApiException(
      error: ApiErrorDto(
        code: code,
        message: message,
        requestId: 'client',
      ),
      statusCode: statusCode,
      retryable: retryable,
      cause: cause,
    );
  }

  Map<String, String> _idempotencyHeaders(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(key, 'idempotencyKey', 'must not be empty');
    }
    return {'Idempotency-Key': normalized};
  }

  Uri _uri(
    String path, {
    Map<String, String>? queryParameters,
  }) =>
      _apiBaseUri.replace(
        path: '${_apiBaseUri.path}$path',
        queryParameters: queryParameters,
        fragment: null,
      );

  static Uri _normalizeApiBaseUri(Uri baseUri) {
    if (!baseUri.hasScheme || baseUri.host.isEmpty) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must be an absolute URI');
    }
    var path = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/api/v1')) path = '$path/api/v1';
    return baseUri.replace(path: path, query: null, fragment: null);
  }

  static String _segment(String value) => Uri.encodeComponent(value);

  static bool _isRetryableStatus(int statusCode) => switch (statusCode) {
        408 || 425 || 429 || 500 || 502 || 503 || 504 => true,
        _ => false,
      };
}

JsonObject _jsonObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      // Report a protocol error below.
    }
  }
  throw FormatException('$field must be a JSON object');
}

List<Object?> _jsonArray(Object? value, String field) {
  if (value is List) return List<Object?>.from(value);
  throw FormatException('$field must be a JSON array');
}
