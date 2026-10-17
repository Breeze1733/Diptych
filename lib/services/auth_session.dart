import 'dart:async';

/// The active server-issued session. Revision checks prevent an old task from
/// sending or publishing a response under a later login, including the same user.
class AuthSession {
  AuthSession._();

  static String? _userId;
  static String? _token;
  static DateTime? _expiresAt;
  static int _revision = 0;
  static Timer? _expiryTimer;
  static final _invalidations = StreamController<int>.broadcast();

  /// Emitted asynchronously after expiry or a current private request's 401.
  /// Consumers compare the emitted revision before clearing any UI state.
  static Stream<int> get invalidations => _invalidations.stream;

  static int get revision => _revision;

  static void ensureRevision(int expected) {
    if (_revision != expected) throw const AuthSessionChangedException();
  }

  static String? get userId => token == null ? null : _userId;

  static String? get token {
    final expiry = _expiresAt;
    if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) return null;
    return _token;
  }

  static void set({
    required String userId,
    required String token,
    required DateTime expiresAt,
  }) {
    if (!const {'A', 'B'}.contains(userId) ||
        token.isEmpty ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Invalid server session');
    }
    _userId = userId;
    _token = token;
    _expiresAt = expiresAt.toUtc();
    _revision++;
    _expiryTimer?.cancel();
    final sessionRevision = _revision;
    _expiryTimer = Timer(
      _expiresAt!.difference(DateTime.now().toUtc()),
      () => invalidate(expectedRevision: sessionRevision),
    );
  }

  static void invalidate({required int expectedRevision}) {
    if (_revision != expectedRevision) return;
    clear();
    _invalidations.add(_revision);
  }

  static void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _userId = null;
    _token = null;
    _expiresAt = null;
    _revision++;
  }
}

class AuthSessionChangedException implements Exception {
  const AuthSessionChangedException();

  @override
  String toString() => '登录状态已变化，请重新操作';
}
