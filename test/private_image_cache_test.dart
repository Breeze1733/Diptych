import 'dart:async';

import 'package:diptych/services/image_download_progress.dart';
import 'package:diptych/services/private_image_cache.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('limits downloads to six until response bodies finish', () async {
    final harness = _DownloadHarness();
    addTearDown(harness.dispose);
    const limit = PrivateImageCache.maxConcurrentDownloads;
    final urls = List.generate(
      limit + 2,
      (index) => 'https://images.test/$index.jpg',
    );
    final files = urls.map(harness.cache.getSingleFile).toList();

    await harness.waitForStarts(limit);
    await Future<void>.delayed(Duration.zero);
    expect(harness.started, urls.take(limit));
    expect(
      harness.cache.downloads.current(urls[limit]).phase,
      ImageDownloadPhase.queued,
    );
    expect(
      harness.cache.downloads.current(urls[limit + 1]).phase,
      ImageDownloadPhase.queued,
    );

    // Receiving headers and a partial body must not free a download slot.
    final quarter = harness.cache.downloads
        .watch(urls.first)
        .firstWhere((progress) => progress.receivedBytes == 25);
    harness.transfers[urls.first]!.add(25);
    expect((await quarter).percent, 25);
    expect(harness.started, hasLength(limit));

    await harness.transfers[urls.first]!.finish();
    await harness.waitForStarts(limit + 1);
    expect(harness.started, urls.take(limit + 1));
    expect(
      harness.cache.downloads.current(urls.last).phase,
      ImageDownloadPhase.queued,
    );

    for (var index = 1; index < urls.length; index++) {
      await harness.waitForStarts(index + 1);
      await harness.transfers[urls[index]]!.finish();
    }
    final results = await Future.wait(files);
    expect(await results.first.length(), 100);
    expect(harness.cache.downloads.current(urls.first).percent, 100);
  });

  test('shares one transfer between a preload and a visible image', () async {
    final harness = _DownloadHarness();
    addTearDown(harness.dispose);
    const url = 'https://images.test/shared.jpg';
    final preload = harness.cache.getSingleFile(url);
    await harness.waitForStarts(1);
    final visible = harness.cache
        .getFileStream(url, withProgress: true)
        .toList();
    await Future<void>.delayed(Duration.zero);
    expect(harness.started, [url]);

    final halfway = harness.cache.downloads
        .watch(url)
        .firstWhere((progress) => progress.receivedBytes == 50);
    harness.transfers[url]!.add(50);
    expect((await halfway).percent, 50);
    await harness.transfers[url]!.finish();
    await preload;
    expect((await visible).whereType<FileInfo>(), hasLength(1));
    expect(harness.cache.downloads.current(url).percent, 100);
    await harness.cache.getSingleFile(url);
    expect(harness.started, hasLength(1));
  });

  test('failed downloads release a slot and can be retried', () async {
    final harness = _DownloadHarness();
    addTearDown(harness.dispose);
    const limit = PrivateImageCache.maxConcurrentDownloads;
    final urls = List.generate(
      limit + 1,
      (index) => 'https://images.test/$index.jpg',
    );
    final files = urls.map(harness.cache.getSingleFile).toList();
    final failure = expectLater(files.first, throwsA(isA<StateError>()));
    await harness.waitForStarts(limit);
    harness.transfers[urls.first]!.body.addError(StateError('connection lost'));
    unawaited(harness.transfers[urls.first]!.body.close());
    await failure;
    await harness.waitForStarts(limit + 1);
    expect(
      harness.cache.downloads.current(urls.first).phase,
      ImageDownloadPhase.failed,
    );

    final retry = harness.cache.getSingleFile(urls.first);
    await Future<void>.delayed(Duration.zero);
    expect(
      harness.cache.downloads.current(urls.first).phase,
      ImageDownloadPhase.queued,
    );
    await harness.transfers[urls[1]]!.finish();
    await harness.waitForStarts(limit + 2);
    expect(harness.started.last, urls.first);
    for (final url in [...urls.skip(2), urls.first]) {
      await harness.transfers[url]!.finish();
    }
    await Future.wait([...files.skip(1), retry]);
    expect(harness.cache.downloads.current(urls.first).percent, 100);
  });

  test(
    'unknown response length reports bytes without inventing a percent',
    () async {
      final harness = _DownloadHarness(totalBytes: null);
      addTearDown(harness.dispose);
      const url = 'https://images.test/chunked.jpg';
      final file = harness.cache.getSingleFile(url);
      await harness.waitForStarts(1);
      harness.transfers[url]!.add(65536);
      await Future<void>.delayed(Duration.zero);
      final progress = harness.cache.downloads.current(url);
      expect(progress.receivedBytes, 65536);
      expect(progress.percent, isNull);
      await harness.transfers[url]!.finish();
      await file;
      expect(harness.cache.downloads.current(url).percent, 100);
    },
  );
}

class _DownloadHarness {
  _DownloadHarness({this.totalBytes = 100}) {
    cache = PrivateImageCache.forTesting(
      repo: NonStoringObjectProvider(),
      fileSystem: MemoryCacheSystem(),
      clientFactory: () => MockClient.streaming((request, _) async {
        final url = request.url.toString();
        final transfer = _Transfer(totalBytes);
        transfers[url] = transfer;
        started.add(url);
        _starts.add(started.length);
        return http.StreamedResponse(
          transfer.body.stream,
          200,
          contentLength: totalBytes,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
    );
  }

  final int? totalBytes;
  late final PrivateImageCache cache;
  final started = <String>[];
  final transfers = <String, _Transfer>{};
  final _starts = StreamController<int>.broadcast();

  Future<void> waitForStarts(int count) async {
    if (started.length >= count) return;
    await _starts.stream
        .firstWhere((value) => value >= count)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    await cache.dispose();
    await cache.downloads.dispose();
    await _starts.close();
  }
}

class _Transfer {
  _Transfer(this.totalBytes);

  final int? totalBytes;
  final body = StreamController<List<int>>();
  int sent = 0;

  void add(int bytes) {
    sent += bytes;
    body.add(List.filled(bytes, 1));
  }

  Future<void> finish() async {
    if (totalBytes != null && sent < totalBytes!) {
      add(totalBytes! - sent);
    }
    await body.close();
  }
}
