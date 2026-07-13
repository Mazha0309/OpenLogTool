import 'dart:async';

import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/server_api.dart';

/// Issues generation-scoped views over token stores.
///
/// A [ServerApi] keeps the token store it was constructed with. Rotating to a
/// new scope therefore prevents an older API context from reading, replacing,
/// or clearing credentials that belong to the current context, even when both
/// backing stores address the same platform-secure key.
final class ScopedTokenStoreCoordinator {
  int _generation = 0;
  Future<void> _operations = Future<void>.value();

  TokenStore scope(TokenStore delegate) {
    final generation = ++_generation;
    return _ScopedTokenStore(this, delegate, generation);
  }

  /// Clears a retired scope's backing store without making the retired scope
  /// usable again.
  ///
  /// The cleanup is serialized ahead of subsequently requested operations, so
  /// a write from the new scope always wins over this cleanup.
  Future<void> clearRetired(TokenStore store) {
    if (store
        case _ScopedTokenStore(
          coordinator: final coordinator,
          delegate: final delegate,
        ) when identical(coordinator, this)) {
      return _enqueue(delegate.clear);
    }
    return _enqueue(store.clear);
  }

  void invalidateCurrentScope() {
    _generation += 1;
  }

  bool _isCurrent(int generation) => generation == _generation;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

final class _ScopedTokenStore implements TokenStore {
  const _ScopedTokenStore(this.coordinator, this.delegate, this.generation);

  final ScopedTokenStoreCoordinator coordinator;
  final TokenStore delegate;
  final int generation;

  @override
  Future<AuthSessionDto?> read() {
    if (!coordinator._isCurrent(generation)) {
      return Future<AuthSessionDto?>.value();
    }
    return coordinator._enqueue(() async {
      if (!coordinator._isCurrent(generation)) return null;
      final session = await delegate.read();
      return coordinator._isCurrent(generation) ? session : null;
    });
  }

  @override
  Future<void> write(AuthSessionDto session) {
    if (!coordinator._isCurrent(generation)) return Future<void>.value();
    return coordinator._enqueue(() async {
      if (!coordinator._isCurrent(generation)) return;
      await delegate.write(session);
    });
  }

  @override
  Future<void> clear() {
    if (!coordinator._isCurrent(generation)) return Future<void>.value();
    return coordinator._enqueue(() async {
      if (!coordinator._isCurrent(generation)) return;
      await delegate.clear();
    });
  }
}
