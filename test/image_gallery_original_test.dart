import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:diptych/services/private_image_cache.dart';
import 'package:diptych/widgets/image_gallery.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file/file.dart' as cache_file;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_view/photo_view.dart';

import 'support/memory_cache_repository.dart';

const _url = 'https://images.test/uploads/photo.png';
late List<int> _previewBytes, _originalBytes;

Future<List<int>> _png(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> _settle(WidgetTester tester, {bool Function()? until}) async {
  for (var index = 0; index < (until == null ? 20 : 300); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (until?.call() == true) return;
  }
  if (until != null) fail('Image operation did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _previewBytes = await _png(30, 20, Colors.blueGrey);
    _originalBytes = await _png(150, 100, Colors.green);
  });

  testWidgets(
    'entering the viewer requests previews only; original button upgrades decoded pixels',
    (tester) async {
      final harness = await _GalleryHarness.create(tester);
      await tester.runAsync(() => harness.cache.getSingleFile(_url));
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImage(
            urls: const [_url],
            cacheManager: harness.cache,
          ),
        ),
      );
      await _settle(tester);
      expect(harness.originalRequests, 0);
      expect(find.textContaining('查看原图'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const ValueKey('view-original-button')));
      await _settle(
        tester,
        until: () => find.text('已加载原图').evaluate().isNotEmpty,
      );
      expect(harness.originalRequests, 1);
      expect(find.text('已加载原图'), findsOneWidget);
      final provider =
          tester.widget<PhotoView>(find.byType(PhotoView)).imageProvider
              as CachedNetworkImageProvider;
      expect(provider.cacheKey, startsWith('original:'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());

      // Exercise the second action in the same app session, on another photo.
      const saveUrl = 'https://images.test/uploads/saved.png';
      await tester.runAsync(() => harness.cache.getSingleFile(saveUrl));
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImage(
            urls: const [saveUrl],
            cacheManager: harness.cache,
          ),
        ),
      );
      await _settle(tester);
      expect(harness.originalRequests, 1);
      final saved = File(
        '${harness.directory.path}${Platform.pathSeparator}saved.png',
      );
      await tester.tap(find.byTooltip('下载'));
      await _settle(tester, until: saved.existsSync);
      expect(harness.originalRequests, 2);
      expect(await tester.runAsync(saved.readAsBytes), _originalBytes);
      expect(find.text('已加载原图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'remote editor entries use motion metadata; local still entries hide live controls',
    (tester) async {
      final harness = await _GalleryHarness.create(tester, isMotion: true);
      final info = await tester.runAsync(() => harness.cache.getInfo(_url));
      expect(info?.isMotion, isTrue);
      const entry = PhotoEntry.url(_url);
      expect(entry.isMotion, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImage(
            entries: const [entry],
            cacheManager: harness.cache,
          ),
        ),
      );
      await _settle(
        tester,
        until: () => find.text('实况').evaluate().isNotEmpty,
      );
      expect(find.text('实况'), findsOneWidget);
      expect(harness.originalRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());

      final still = File(
        '${harness.directory.path}${Platform.pathSeparator}still.png',
      );
      await tester.runAsync(() => still.writeAsBytes(_originalBytes));
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImage(
            entries: [PhotoEntry.file(still)],
            cacheManager: harness.cache,
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('实况'), findsNothing);
      expect(harness.originalRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _GalleryHarness {
  _GalleryHarness(this.directory);
  final Directory directory;
  late final PrivateImageCache cache;
  int originalRequests = 0;

  static Future<_GalleryHarness> create(
    WidgetTester tester, {
    bool isMotion = false,
  }) async {
    final directory = await tester.runAsync(
      () => Directory('.dart_tool').createTemp('gallery-test-'),
    );
    final harness = _GalleryHarness(directory!);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'com.splitmoments.split_moments/foreground_service',
      'com.splitmoments.split_moments/wakelock',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => harness.directory.absolute.path,
    );
    await tester.runAsync(() async {
      harness.cache = PrivateImageCache.forTesting(
        repo: MemoryCacheRepository(),
        fileSystem: _TestDiskCache(harness.directory),
        supportsPreviews: (url) => url.startsWith('https://images.test/'),
        clientFactory: () => MockClient((request) async {
          final variant = request.url.queryParameters['variant'];
          final info = {
            'original_bytes': _originalBytes.length,
            'width': 150,
            'height': 100,
            'is_motion': isMotion,
          };
          if (variant == 'info') {
            return http.Response(
              jsonEncode({'ok': true, 'data': info}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (variant == 'preview') {
            return http.Response.bytes(
              _previewBytes,
              200,
              headers: {
                'content-type': 'image/png',
                'x-image-variant': 'preview',
                'x-image-motion': isMotion ? '1' : '0',
                'x-original-size': '${_originalBytes.length}',
                'x-image-width': '150',
                'x-image-height': '100',
                'cache-control': 'private, max-age=86400',
              },
            );
          }
          harness.originalRequests++;
          return http.Response.bytes(
            _originalBytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
    });
    addTearDown(() async {
      await harness.cache.dispose();
      await harness.cache.downloads.dispose();
      final allowed = Directory('.dart_tool').absolute.path;
      if (!harness.directory.absolute.path.startsWith(
        '$allowed${Platform.pathSeparator}',
      )) {
        throw StateError('Test directory escaped workspace');
      }
      await tester.runAsync(() => harness.directory.delete(recursive: true));
      for (final channel in [
        'plugins.flutter.io/path_provider',
        'com.splitmoments.split_moments/foreground_service',
        'com.splitmoments.split_moments/wakelock',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
    });
    await tester.pump();
    return harness;
  }
}

class _TestDiskCache implements FileSystem {
  _TestDiskCache(Directory directory)
    : _directory = Directory('${directory.path}${Platform.pathSeparator}cache')
          .create();
  final Future<Directory> _directory;
  @override
  Future<cache_file.File> createFile(String name) async {
    final directory = await _directory;
    return const LocalFileSystem().file(
      '${directory.absolute.path}${Platform.pathSeparator}$name',
    );
  }
}
