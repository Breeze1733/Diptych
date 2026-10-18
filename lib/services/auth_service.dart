import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_config.dart';
import 'auth_session.dart';
import 'http_request.dart';

class AuthLoginException implements Exception {
  const AuthLoginException(this.message);

  final String message;
}

/// 登录口令只交给服务器校验，不再编译进客户端或保存到本机。
class AuthService {
  static const _keySession = 'auth_session_v1';
  static int _operation = 0;
  static Future<void> _pending = Future<void>.value();

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  static void _checkOperation(int operation) {
    if (operation != _operation) throw const AuthSessionChangedException();
  }

  Future<String?> login(String key) async {
    final operation = ++_operation;
    final revision = AuthSession.revision;
    final response = await runHttpRequest(
      (client) => client.post(
        Uri.parse('${ApiConfig.apiBaseUrl}/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key}),
      ),
      timeout: const Duration(seconds: 15),
      sessionRevision: revision,
    );
    _checkOperation(operation);
    if (response.statusCode == 401) return null;
    if (response.statusCode == 429) {
      throw const AuthLoginException('尝试次数过多，请稍后再试');
    }
    if (response.statusCode != 200) {
      throw const AuthLoginException('登录服务暂不可用，请稍后重试');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw const FormatException('服务器未确认登录');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('登录响应缺少会话');
    }
    final role = data['user_id'];
    final token = data['token'];
    final expiryValue = data['expires_at'];
    final expiry = expiryValue is String
        ? DateTime.tryParse(expiryValue)
        : null;
    if (role is! String ||
        !const {'A', 'B'}.contains(role) ||
        token is! String ||
        token.isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('服务器返回的会话无效');
    }
    return _serialize(() async {
      _checkOperation(operation);
      try {
        final prefs = await SharedPreferences.getInstance();
        _checkOperation(operation);
        // 用单个清单提交，避免口令/角色/有效期分步写入时形成混合会话。
        final saved = await prefs.setString(
          _keySession,
          jsonEncode({
            'user_id': role,
            'token': token,
            'expires_at': expiry.toIso8601String(),
          }),
        );
        if (operation != _operation) {
          // This transaction owns the serial queue, so a later login has not
          // committed yet. Remove only this stale commit before handing it on.
          await prefs.remove(_keySession);
          throw const AuthSessionChangedException();
        }
        if (!saved) throw StateError('无法保存登录状态');
        AuthSession.set(userId: role, token: token, expiresAt: expiry);
        return role;
      } on AuthSessionChangedException {
        rethrow;
      } catch (_, stackTrace) {
        Error.throwWithStackTrace(
          const AuthLoginException('无法保存本机登录状态，请更新应用后重试'),
          stackTrace,
        );
      }
    });
  }

  /// 旧版只有角色的登录态需要重新输入一次口令，不能据此签发服务端凭据。
  Future<String?> getUserRole() {
    final operation = _operation;
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      if (operation != _operation) return null;
      Object? decoded;
      try {
        decoded = jsonDecode(prefs.getString(_keySession) ?? 'null');
      } on FormatException {
        decoded = null;
      }
      if (decoded is Map<String, dynamic>) {
        final role = decoded['user_id'];
        final token = decoded['token'];
        final expiry = DateTime.tryParse(
          decoded['expires_at']?.toString() ?? '',
        );
        if (role is String &&
            const {'A', 'B'}.contains(role) &&
            token is String &&
            token.isNotEmpty &&
            expiry != null &&
            expiry.isAfter(DateTime.now().toUtc())) {
          AuthSession.set(userId: role, token: token, expiresAt: expiry);
          return role;
        }
      }
      AuthSession.clear();
      await _clearPreferences(prefs);
      return null;
    });
  }

  Future<void> logout() {
    ++_operation;
    AuthSession.clear();
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      await _clearPreferences(prefs);
    });
  }

  static Future<void> _clearPreferences(SharedPreferences prefs) async {
    for (final key in const [
      _keySession,
      'user_role',
      'auth_session_token',
      'auth_session_expires_at',
    ]) {
      await prefs.remove(key);
    }
  }
}
