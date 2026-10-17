import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_http_client.dart';
import 'auth_session.dart';

/// 普通 JSON API：正文读完才算完成，避免只给响应头设置超时。
class HttpRequests {
  HttpRequests() : _sessionRevision = AuthSession.revision;

  final int _sessionRevision;

  Future<T> _request<T>(
    Future<T> Function(http.Client) request, {
    Duration timeout = const Duration(seconds: 25),
  }) => runHttpRequest(
    request,
    timeout: timeout,
    sessionRevision: _sessionRevision,
  );

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 25),
  }) =>
      _request((client) => client.get(url, headers: headers), timeout: timeout);

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  }) => _request(
    (client) => client.post(url, headers: headers, body: body),
    timeout: timeout,
  );

  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _request((client) => client.put(url, headers: headers, body: body));

  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _request((client) => client.delete(url, headers: headers, body: body));
}

/// 每次请求持有独立连接，截止时间覆盖请求发送和完整响应正文。
/// Future.timeout 本身不会取消网络请求，因此超时也必须关闭 client。
Future<T> runHttpRequest<T>(
  Future<T> Function(http.Client client) request, {
  Duration timeout = const Duration(seconds: 25),
  http.Client Function() clientFactory = ApiHttpClient.create,
  int? sessionRevision,
}) async {
  if (sessionRevision != null) AuthSession.ensureRevision(sessionRevision);
  final client = clientFactory();
  try {
    final response = await request(client).timeout(
      timeout,
      onTimeout: () {
        client.close();
        throw TimeoutException('网络请求超时', timeout);
      },
    );
    if (sessionRevision != null) AuthSession.ensureRevision(sessionRevision);
    return response;
  } finally {
    client.close();
  }
}
