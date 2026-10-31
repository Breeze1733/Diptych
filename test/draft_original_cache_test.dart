import 'dart:io';

import 'package:diptych/services/draft_service.dart';
import 'package:diptych/services/private_image_cache.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PrivateImageCache cache;
  var requests = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-transfer-cache-');
    requests = 0;
    cache = PrivateImageCache.forTesting(
      repo: MemoryCacheRepository(),
      fileSystem: MemoryCacheSystem(),
      supportsPreviews: (_) => true,
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response('unexpected download', 500);
      }),
    );
  });
  tearDown(() async {
    await cache.dispose();
    await cache.downloads.dispose();
    if (temp.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !temp.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('diptych-transfer-cache-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  test('published originals keep their full motion bytes after draft files are removed', () async {
    const url = 'https://images.test/uploads/original.jpg';
    const removed = 'https://images.test/uploads/removed.jpg';
    final bytes = [255, 216, 255, 217, ...'original-motion-video'.codeUnits];
    final source = await File('${temp.path}/original.jpg').writeAsBytes(bytes);
    await MomentDraftStore.transferToMomentCache(
      [
        DraftPhotoItem(
          isLocal: true,
          file: source,
          uploadedUrl: url,
          isMotion: true,
          uploadLive: true,
        ),
        DraftPhotoItem(isLocal: true, file: source, uploadedUrl: removed),
      ],
      [url],
      cache: cache,
    );
    await source.delete();
    expect(await (await cache.getOriginalFile(url)).readAsBytes(), bytes);
    expect(await cache.getOriginalFromCache(removed), isNull);
    expect(requests, 0);
  });

  test('a missing optional cache source does not stop other originals from being retained', () async {
    const missing = 'https://images.test/uploads/missing.jpg';
    const good = 'https://images.test/uploads/good.jpg';
    final source = await File('${temp.path}/good.jpg').writeAsBytes([1, 2, 3]);
    await MomentDraftStore.transferToMomentCache(
      [
        DraftPhotoItem(
          isLocal: true,
          file: File('${temp.path}/missing.jpg'),
          uploadedUrl: missing,
        ),
        DraftPhotoItem(isLocal: true, file: source, uploadedUrl: good),
      ],
      [missing, good],
      cache: cache,
    );
    expect(await (await cache.getOriginalFile(good)).readAsBytes(), [1, 2, 3]);
    expect(requests, 0);
  });
}
