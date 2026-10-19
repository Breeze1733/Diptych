import 'dart:async';
import 'dart:convert';

import 'package:diptych/services/image_download_progress.dart';
import 'package:diptych/services/private_image_cache.dart';
import 'package:diptych/utils/image_request_urls.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_cache_repository.dart';

const _url = 'https://images.test/uploads/photo.jpg';
const _preview = [1, 2, 3];
const _original = [10, 20, 30, 40, 50, 60];
const _headers = {
  'content-type': 'image/webp',
  'x-image-variant': 'preview',
  'x-original-size': '6',
  'x-image-width': '4000',
  'x-image-height': '3000',
  'x-image-motion': '0',
  'cache-control': 'private, max-age=86400',
};

PrivateImageCache _cache(Future<http.Response> Function(http.Request) handler) {
  final cache = PrivateImageCache.forTesting(
    repo: MemoryCacheRepository(),
    fileSystem: MemoryCacheSystem(),
    supportsPreviews: (url) => url.startsWith('https://images.test/'),
    clientFactory: () => MockClient(handler),
  );
  addTearDown(() async {
    await cache.dispose();
    await cache.downloads.dispose();
  });
  return cache;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'normal reads request only the unique preview and reuse its metadata',
    () async {
      final requests = <Uri>[];
      final cache = _cache((request) async {
        requests.add(request.url);
        return http.Response.bytes(_preview, 200, headers: _headers);
      });
      final file = await cache.getSingleFile(_url);
      expect(await file.readAsBytes(), _preview);
      expect(requests.single.queryParameters, {
        'variant': 'preview',
        'pv': '1',
      });
      expect(await cache.getOriginalFromCache(_url), isNull);
      expect((await cache.getInfo(_url))?.originalBytes, 6);
      expect((await cache.getInfo(_url))?.isMotion, false);
      expect(requests, hasLength(1));
      expect(await (await cache.getSingleFile(_url)).readAsBytes(), _preview);
      expect(requests, hasLength(1));
    },
  );

  test('view original and save share one transfer, promote the cache and remove the preview', () async {
    final release = Completer<void>();
    var originalRequests = 0;
    final cache = _cache((request) async {
      if (request.url.queryParameters['variant'] == 'preview') {
        return http.Response.bytes(_preview, 200, headers: _headers);
      }
      originalRequests++;
      await release.future;
      return http.Response.bytes(
        _original,
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    await cache.getSingleFile(_url);
    final view = cache.getOriginalFile(_url);
    final save = cache.getOriginalFile(_url);
    await Future<void>.delayed(Duration.zero);
    expect(originalRequests, 1);
    release.complete();
    final files = await Future.wait([view, save]);
    expect(await files.first.readAsBytes(), _original);
    expect(files.first.path, files.last.path);
    expect(cache.isOriginalKnown(_url), true);
    expect(await cache.getFileFromCache('preview-v1:$_url'), isNull);
    expect(await (await cache.getSingleFile(_url)).readAsBytes(), _original);
    expect(originalRequests, 1);
  });

  test('failed original retains the preview and can be retried', () async {
    var fail = true;
    final cache = _cache((request) async {
      if (request.url.queryParameters['variant'] == 'preview') {
        return http.Response.bytes(_preview, 200, headers: _headers);
      }
      return fail
          ? http.Response('failed', 503)
          : http.Response.bytes(
              _original,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
    });
    await cache.getSingleFile(_url);
    await expectLater(
      cache.getOriginalFile(_url),
      throwsA(isA<HttpExceptionWithStatus>()),
    );
    expect(await cache.getOriginalFromCache(_url), isNull);
    expect(await (await cache.getSingleFile(_url)).readAsBytes(), _preview);
    fail = false;
    expect(await (await cache.getOriginalFile(_url)).readAsBytes(), _original);
  });

  test(
    'a late background preview cannot downgrade an already downloaded original',
    () async {
      final releasePreview = Completer<void>();
      final previewStarted = Completer<void>();
      final cache = _cache((request) async {
        if (request.url.queryParameters['variant'] == 'preview') {
          previewStarted.complete();
          await releasePreview.future;
          return http.Response.bytes(_preview, 200, headers: _headers);
        }
        return http.Response.bytes(
          _original,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      final preload = cache.getSingleFile(_url);
      await previewStarted.future;
      await cache.getOriginalFile(_url);
      releasePreview.complete();
      expect(await (await preload).readAsBytes(), _original);
      expect(await cache.getFileFromCache('preview-v1:$_url'), isNull);
      expect(cache.isOriginalKnown(_url), true);
    },
  );

  test('an old backend ignoring preview parameters is rejected without fetching the original URL', () async {
    final requested = <Uri>[];
    final cache = _cache((request) async {
      requested.add(request.url);
      return http.Response.bytes(
        _original,
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    await expectLater(cache.getSingleFile(_url), throwsA(isA<StateError>()));
    expect(requested.single.queryParameters['variant'], 'preview');
    expect(await cache.getOriginalFromCache(_url), isNull);
  });

  test('preparing responses show preparation state and never become cached image bytes', () async {
    var count = 0;
    final cache = _cache((request) async {
      if (count++ == 0) {
        return http.Response(
          '{}',
          202,
          headers: {'x-image-state': 'preparing'},
        );
      }
      return http.Response.bytes(_preview, 200, headers: _headers);
    });
    final phases = <ImageDownloadPhase>[];
    final subscription = cache.downloads
        .watch(_url)
        .listen((state) => phases.add(state.phase));
    addTearDown(subscription.cancel);
    expect(await (await cache.getSingleFile(_url)).readAsBytes(), _preview);
    expect(phases, contains(ImageDownloadPhase.preparing));
    expect(count, 2);
  });

  test(
    'metadata requests retrieve JSON without downloading original bytes',
    () async {
      final cache = _cache((request) async {
        expect(request.url.queryParameters['variant'], 'info');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'original_bytes': 6000000,
              'width': 4000,
              'height': 3000,
              'is_motion': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final info = await cache.getInfo(_url);
      expect(info?.isMotion, true);
      expect(info?.originalBytes, 6000000);
      expect(await cache.getOriginalFromCache(_url), isNull);
    },
  );

  test('preview request URLs round-trip without changing existing query parameters', () {
    const url = 'https://images.test/uploads/a.jpg?token=test';
    expect(
      ImageRequestUrls.original(ImageRequestUrls.variant(url, 'preview')),
      url,
    );
    expect(
      ImageRequestUrls.original(ImageRequestUrls.variant(_url, 'preview')),
      _url,
    );
  });
}
