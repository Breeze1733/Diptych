import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:file/file.dart' as cache_file;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../models/image_media_info.dart';
import '../utils/image_request_urls.dart';
import 'api_http_client.dart';
import 'auth_session.dart';
import 'image_download_progress.dart';

/// Keeps original URLs in the data model; ordinary reads fetch only previews.
class PrivateImageCache extends CacheManager {
  PrivateImageCache._() : this._configured(_ImageCacheState());

  PrivateImageCache._configured(
    this._state, {
    CacheInfoRepository? repo,
    FileSystem? fileSystem,
  }) : super(
         repo != null && fileSystem != null
             ? Config(
                 DefaultCacheManager.key,
                 repo: repo,
                 fileSystem: fileSystem,
                 fileService: _PrivateFileService(_state),
               )
             : Config(
                 DefaultCacheManager.key,
                 fileService: _PrivateFileService(_state),
               ),
       ) {
    _state.persistInfo = (url, info) async {
      await super.putFile(
        _infoKey(url),
        Uint8List.fromList(utf8.encode(jsonEncode(info.toJson()))),
        fileExtension: 'json',
      );
    };
  }

  @visibleForTesting
  PrivateImageCache.forTesting({
    required CacheInfoRepository repo,
    required FileSystem fileSystem,
    required http.Client Function() clientFactory,
    bool Function(String)? supportsPreviews,
  }) : this._configured(
         _ImageCacheState(
           clientFactory: clientFactory,
           supportsPreviews: supportsPreviews ?? (_) => false,
         ),
         repo: repo,
         fileSystem: fileSystem,
       );

  static const maxConcurrentDownloads = 6;
  static String _previewKey(String url) => 'preview-v1:$url';
  static String _infoKey(String url) => 'media-info-v1:$url';
  final _ImageCacheState _state;
  final _originalJobs = <String, Future<File>>{};
  final _infoJobs = <String, Future<ImageMediaInfo?>>{};
  static final PrivateImageCache _instance = PrivateImageCache._();
  factory PrivateImageCache() => _instance;

  ImageDownloadTracker get downloads => _state.downloads;
  Stream<String> get changes => _state.changes.stream;
  bool supportsPreviews(String url) => _state.supportsPreviews(url);
  ImageMediaInfo? mediaInfo(String url) => _state.infos[url];
  bool isOriginalKnown(String url) => _state.originals.contains(url);
  String displayKey(String url) =>
      '${isOriginalKnown(url) ? 'original' : 'preview-v1'}:$url';
  String progressKey(String url, {bool original = false}) =>
      original && supportsPreviews(url) ? 'original:$url' : url;

  Future<FileInfo?> getOriginalFromCache(String url) async {
    final file = await super.getFileFromCache(url);
    if (file != null) {
      _state.markOriginal(url);
    } else if (_state.originals.remove(url)) {
      _state.changes.add(url);
    }
    return file;
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    if (!supportsPreviews(key)) {
      return super.getFileFromCache(key, ignoreMemCache: ignoreMemCache);
    }
    return await getOriginalFromCache(key) ??
        await super.getFileFromCache(
          _previewKey(key),
          ignoreMemCache: ignoreMemCache,
        );
  }

  @override
  Future<cache_file.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    final cached = await getFileFromCache(url);
    if (cached != null &&
        (isOriginalKnown(url) || cached.validTill.isAfter(DateTime.now()))) {
      return cached.file;
    }
    return (await downloadFile(url, key: key, authHeaders: headers)).file;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final original = supportsPreviews(url)
        ? await getOriginalFromCache(url)
        : null;
    if (original != null) {
      yield original;
      return;
    }
    final preview = supportsPreviews(url);
    downloads.queue(url);
    try {
      await for (final result in super.getFileStream(
        preview ? ImageRequestUrls.variant(url, 'preview') : url,
        key: preview ? _previewKey(url) : key ?? url,
        headers: headers,
        withProgress: withProgress,
      )) {
        if (result is FileInfo && preview) {
          yield await getOriginalFromCache(url) ?? result;
        } else {
          yield result;
        }
      }
      downloads.complete(url);
      if (preview && isOriginalKnown(url)) {
        await super.removeFile(_previewKey(url));
      }
    } catch (_) {
      downloads.fail(url);
      rethrow;
    }
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    final preview = supportsPreviews(url);
    if (preview) {
      final original = await getOriginalFromCache(url);
      if (original != null) return original;
    }
    downloads.queue(url);
    try {
      final result = await super.downloadFile(
        preview ? ImageRequestUrls.variant(url, 'preview') : url,
        key: preview ? _previewKey(url) : key ?? url,
        authHeaders: authHeaders,
        force: force,
      );
      downloads.complete(url);
      if (preview) {
        final original = await getOriginalFromCache(url);
        if (original != null) {
          await super.removeFile(_previewKey(url));
          return original;
        }
      }
      return result;
    } catch (_) {
      downloads.fail(url);
      rethrow;
    }
  }

  /// Explicit requests share one original transfer; failure retains the preview.
  Future<File> getOriginalFile(String url) async {
    if (_originalJobs.containsKey(url)) return _originalJobs[url]!;
    final job = _loadOriginal(url);
    _originalJobs[url] = job;
    try {
      return await job;
    } finally {
      if (identical(_originalJobs[url], job)) _originalJobs.remove(url);
    }
  }

  Future<File> _loadOriginal(String url) async {
    final cached = await getOriginalFromCache(url);
    if (cached != null) return cached.file;
    final revision = AuthSession.revision;
    final progress = progressKey(url, original: true);
    downloads.queue(progress);
    try {
      final file = await super.downloadFile(url, key: url);
      AuthSession.ensureRevision(revision);
      // The original is completely written before changing the active quality.
      // Evict decoded preview pixels only, preserving the downloaded disk file.
      await CachedNetworkImageProvider(url, cacheKey: displayKey(url)).evict();
      _state.markOriginal(url);
      await super.removeFile(_previewKey(url));
      downloads.complete(progress);
      return file.file;
    } catch (_) {
      downloads.fail(progress);
      rethrow;
    }
  }

  Future<ImageMediaInfo?> getInfo(String url) async {
    if (_state.infos.containsKey(url)) return _state.infos[url];
    if (!supportsPreviews(url)) return null;
    if (_infoJobs.containsKey(url)) return _infoJobs[url]!;
    final job = _loadInfo(url);
    _infoJobs[url] = job;
    try {
      return await job;
    } finally {
      if (identical(_infoJobs[url], job)) _infoJobs.remove(url);
    }
  }

  Future<ImageMediaInfo?> _loadInfo(String url) async {
    try {
      final persisted = await super.getFileFromCache(_infoKey(url));
      if (persisted != null) {
        final info = ImageMediaInfo.fromJson(
          jsonDecode(await persisted.file.readAsString())
              as Map<String, dynamic>,
        );
        _state.infos[url] = info;
        return info;
      }
      final response = await super.downloadFile(
        ImageRequestUrls.variant(url, 'info'),
        key: 'info-response:$url',
      );
      final body = jsonDecode(
        await response.file.readAsString(),
      ) as Map<String, dynamic>;
      final info = ImageMediaInfo.fromJson(
        body['data'] as Map<String, dynamic>,
      );
      await _state.recordInfo(url, info);
      return info;
    } catch (_) {
      return null;
    }
  }

  /// Uploads already possess the original; seed without another transfer.
  Future<File> cacheOriginal(String url, File source) async {
    final extension = source.path.split('.').last.toLowerCase();
    final file = await super.putFileStream(
      url,
      source.openRead(),
      fileExtension: extension,
    );
    _state.markOriginal(url);
    await super.removeFile(_previewKey(url));
    return file;
  }

  @override
  Future<void> removeFile(String key) async {
    await super.removeFile(key);
    await super.removeFile(_previewKey(key));
    await super.removeFile(_infoKey(key));
    await super.removeFile('info-response:$key');
    _state.originals.remove(key);
    _state.infos.remove(key);
    _state.changes.add(key);
  }

  @override
  Future<void> emptyCache() async {
    await super.emptyCache();
    _state.originals.clear();
    _state.infos.clear();
    _state.changes.add('');
  }
}

class _ImageCacheState {
  _ImageCacheState({
    http.Client Function()? clientFactory,
    bool Function(String)? supportsPreviews,
  }) : clientFactory = clientFactory ?? ApiHttpClient.create,
       supportsPreviews = supportsPreviews ?? ImageRequestUrls.supportsPreview;
  final http.Client Function() clientFactory;
  final bool Function(String) supportsPreviews;
  final downloads = ImageDownloadTracker();
  final changes = StreamController<String>.broadcast();
  final originals = <String>{};
  final infos = <String, ImageMediaInfo>{};
  Future<void> Function(String, ImageMediaInfo)? persistInfo;
  void markOriginal(String url) {
    if (originals.add(url)) changes.add(url);
  }

  Future<void> recordInfo(String url, ImageMediaInfo info) async {
    infos[url] = info;
    changes.add(url);
    try {
      await persistInfo?.call(url, info);
    } catch (_) {
      /* Optional metadata cache. */
    }
  }
}

class _PrivateFileService extends FileService {
  _PrivateFileService(this.state) {
    concurrentFetches = PrivateImageCache.maxConcurrentDownloads;
  }
  final _ImageCacheState state;
  static const _timeout = Duration(seconds: 30);
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final variant = uri.queryParameters['variant'];
    final logical = variant == 'preview' || variant == 'info'
        ? ImageRequestUrls.original(url)
        : url;
    final progressKey = variant == 'info'
        ? 'info:$logical'
        : variant != 'preview' && state.supportsPreviews(logical)
        ? 'original:$logical'
        : logical;
    final revision = AuthSession.revision;
    state.downloads.start(progressKey);
    for (var attempt = 0; attempt < 120; attempt++) {
      AuthSession.ensureRevision(revision);
      final client = state.clientFactory();
      try {
        final request = http.Request('GET', uri);
        if (headers != null) request.headers.addAll(headers);
        request.headers['Accept-Encoding'] = 'identity';
        final response = await client
            .send(request)
            .timeout(
              _timeout,
              onTimeout: () {
                client.close();
                throw TimeoutException('等待图片响应超时');
              },
            );
        AuthSession.ensureRevision(revision);
        if (response.statusCode == 202 &&
            response.headers['x-image-state'] == 'preparing') {
          client.close();
          state.downloads.preparing(progressKey);
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        if (variant == 'preview' &&
            response.statusCode == 200 &&
            response.headers['x-image-variant'] != 'preview') {
          throw StateError('服务器尚未支持图片预览，请先更新后端');
        }
        if (variant == 'info' &&
            response.statusCode == 200 &&
            !(response.headers['content-type'] ?? '').contains(
              'application/json',
            )) {
          throw StateError('服务器尚未支持图片信息');
        }
        if (response.statusCode == 200 &&
            response.headers.containsKey('x-image-motion')) {
          await state.recordInfo(
            logical,
            ImageMediaInfo(
              originalBytes:
                  int.tryParse(response.headers['x-original-size'] ?? '') ?? 0,
              width: int.tryParse(response.headers['x-image-width'] ?? '') ?? 0,
              height:
                  int.tryParse(response.headers['x-image-height'] ?? '') ?? 0,
              isMotion: response.headers['x-image-motion'] == '1',
            ),
          );
        }
        if (response.statusCode != 200) client.close();
        state.downloads.update(progressKey, 0, response.contentLength);
        return _PrivateFileResponse(
          HttpGetResponse(response),
          client,
          progressKey,
          state.downloads,
        );
      } catch (_) {
        client.close();
        state.downloads.fail(progressKey);
        rethrow;
      }
    }
    state.downloads.fail(progressKey);
    throw TimeoutException('预览图生成超时，请重试');
  }
}

class _PrivateFileResponse implements FileServiceResponse {
  _PrivateFileResponse(
    this._response,
    this._client,
    this._key,
    this._downloads,
  );
  final FileServiceResponse _response;
  final http.Client _client;
  final String _key;
  final ImageDownloadTracker _downloads;
  @override
  Stream<List<int>> get content async* {
    try {
      var received = 0;
      await for (final chunk in _response.content.timeout(
        _PrivateFileService._timeout,
      )) {
        received += chunk.length;
        _downloads.update(_key, received, contentLength);
        yield chunk;
      }
      if (contentLength != null && received != contentLength) {
        throw StateError('图片内容不完整，请重试');
      }
      _downloads.complete(_key);
    } catch (_) {
      _downloads.fail(_key);
      rethrow;
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
