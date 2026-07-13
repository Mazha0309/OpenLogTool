import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/scoped_token_store.dart';
import 'package:openlogtool/services/server_api.dart';

void main() {
  test('retired scopes cannot read, overwrite, or clear the current session',
      () async {
    final coordinator = ScopedTokenStoreCoordinator();
    final backing = _SharedTokenBacking();
    final retiredClearStarted = Completer<void>();
    final finishRetiredClear = Completer<void>();
    final retired = coordinator.scope(
      _BackedTokenStore(
        backing,
        beforeClear: () async {
          retiredClearStarted.complete();
          await finishRetiredClear.future;
        },
      ),
    );
    await retired.write(_session('alice'));

    final current = coordinator.scope(_BackedTokenStore(backing));
    final retiredCleanup = coordinator.clearRetired(retired);
    await retiredClearStarted.future;
    final currentWrite = current.write(_session('bob'));
    finishRetiredClear.complete();
    await Future.wait([retiredCleanup, currentWrite]);

    await retired.write(_session('mallory'));
    await retired.clear();
    expect(await retired.read(), isNull);
    expect((await current.read())?.user.username, 'bob');
    expect(backing.session?.refreshToken, 'refresh-bob');
  });

  test('a read that finishes after its scope is retired returns no session',
      () async {
    final coordinator = ScopedTokenStoreCoordinator();
    final backing = _SharedTokenBacking(session: _session('alice'));
    final readStarted = Completer<void>();
    final finishRead = Completer<void>();
    final retired = coordinator.scope(
      _BackedTokenStore(
        backing,
        beforeRead: () async {
          readStarted.complete();
          await finishRead.future;
        },
      ),
    );

    final staleRead = retired.read();
    await readStarted.future;
    final current = coordinator.scope(_BackedTokenStore(backing));
    finishRead.complete();

    expect(await staleRead, isNull);
    expect((await current.read())?.user.username, 'alice');
  });
}

AuthSessionDto _session(String username) => AuthSessionDto(
      accessToken: 'access-$username',
      accessTokenExpiresIn: 900,
      refreshToken: 'refresh-$username',
      refreshTokenExpiresAt: DateTime.utc(2030),
      user: ApiUserDto(
        id: 'user-$username',
        username: username,
        role: 'user',
      ),
    );

final class _SharedTokenBacking {
  _SharedTokenBacking({this.session});

  AuthSessionDto? session;
}

final class _BackedTokenStore implements TokenStore {
  _BackedTokenStore(this.backing, {this.beforeRead, this.beforeClear});

  final _SharedTokenBacking backing;
  final Future<void> Function()? beforeRead;
  final Future<void> Function()? beforeClear;

  @override
  Future<AuthSessionDto?> read() async {
    await beforeRead?.call();
    return backing.session;
  }

  @override
  Future<void> write(AuthSessionDto session) async {
    backing.session = session;
  }

  @override
  Future<void> clear() async {
    await beforeClear?.call();
    backing.session = null;
  }
}
