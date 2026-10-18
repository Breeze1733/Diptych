import 'package:http/http.dart' as http;

import '../constants/api_config.dart';
import 'auth_session.dart';

/// Binds a client to one session and sends its token only to first-party servers.
class ApiHttpClient extends http.BaseClient {
  ApiHttpClient({http.Client? transport})
    : _inner = transport ?? http.Client(),
      _revision = AuthSession.revision,
      _token = AuthSession.token;

  final http.Client _inner;
  final int _revision;
  final String? _token;

  static http.Client create() => ApiHttpClient();

  static final _trustedOrigins = <String>{
    Uri.parse(ApiConfig.apiBaseUrl).origin,
    Uri.parse(ApiConfig.siteUrl).origin,
  };

  static bool _isPrivateResource(Uri uri) {
    final api = Uri.parse(ApiConfig.apiBaseUrl);
    final apiPath = api.path.endsWith('/')
        ? api.path.substring(0, api.path.length - 1)
        : api.path;
    if (uri.origin == api.origin && uri.path.startsWith('$apiPath/')) {
      final path = uri.path.substring(apiPath.length);
      return path != '/auth/login' &&
          path != '/version' &&
          !path.startsWith('/version/');
    }
    return uri.origin == Uri.parse(ApiConfig.siteUrl).origin &&
        uri.path.startsWith('/uploads/');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    AuthSession.ensureRevision(_revision);
    if (_token != AuthSession.token) throw const AuthSessionChangedException();
    // BaseRequest's headers are case insensitive.
    request.headers.remove('Authorization');
    if (_token != null && _trustedOrigins.contains(request.url.origin)) {
      request.headers['Authorization'] = 'Bearer $_token';
      // IOClient follows redirects internally. Letting it do so could forward
      // credentials to a host the app never checked, including a subdomain.
      request.followRedirects = false;
    }
    final response = await _inner.send(request);
    if (response.statusCode == 401 &&
        _token != null &&
        _isPrivateResource(request.url)) {
      AuthSession.invalidate(expectedRevision: _revision);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
