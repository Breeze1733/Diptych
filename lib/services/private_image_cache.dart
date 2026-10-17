import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'api_http_client.dart';

/// Shares the existing disk cache while authenticating private media downloads.
class PrivateImageCache extends CacheManager {
  PrivateImageCache._()
    : super(
        Config(DefaultCacheManager.key, fileService: _PrivateFileService()),
      );

  static final PrivateImageCache _instance = PrivateImageCache._();

  factory PrivateImageCache() => _instance;
}

class _PrivateFileService extends FileService {
  static const _timeout = Duration(seconds: 30);

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = ApiHttpClient.create();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) client.close();
      return _PrivateFileResponse(HttpGetResponse(response), client);
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}

class _PrivateFileResponse implements FileServiceResponse {
  _PrivateFileResponse(this._response, this._client);

  final FileServiceResponse _response;
  final http.Client _client;

  @override
  Stream<List<int>> get content async* {
    try {
      yield* _response.content.timeout(_PrivateFileService._timeout);
    } finally {
      _client.close();
    }
  }

  @override
  int? get contentLength => _response.contentLength;

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill => _response.validTill;

  @override
  String? get eTag => _response.eTag;

  @override
  String get fileExtension => _response.fileExtension;
}
