import 'dart:async';
import 'dart:io';

import 'package:diptych/constants/api_config.dart';
import 'package:diptych/controllers/moment_upload_controller.dart';
import 'package:diptych/services/http_request.dart';
import 'package:diptych/services/storage_service.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _oldUrl = '${ApiConfig.siteUrl}/uploads/old.jpg';
const _newUrl = '${ApiConfig.siteUrl}/uploads/new.jpg';

class _ProbeRequests extends HttpRequests {
  _ProbeRequests(this.probe);

  final Future<http.Response> Function(Uri) probe;
  final urls = <Uri>[];
  Map<String, String>? headers;

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) {
    urls.add(url);
    this.headers = headers;
    return probe(url);
  }
}

class _Storage extends StorageService {
  _Storage(HttpRequests http) : super(http: http);

  int uploads = 0;
  bool failUpload = false;

  @override
  Future<String> uploadImage(
    File file,
    String folder, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
    void Function(String)? onUploadIdCreated,
  }) async {
    uploads++;
    if (failUpload) throw Exception('offline');
    return _newUrl;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    for (final channel in [
      'com.splitmoments.split_moments/foreground_service',
      'com.splitmoments.split_moments/wakelock',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
  });

  MomentUploadController controllerFor(
    _Storage storage,
    List<PhotoEntry> photos, {
    void Function()? onUploaded,
  }) {
    final controller = MomentUploadController(
      storage: storage,
      folder: 'user_A',
      photos: () => photos,
      onUploaded: onUploaded ?? () {},
    );
    addTearDown(() async {
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    return controller;
  }

  for (final status in [404, 410]) {
    test('reuploads a draft whose original was removed ($status)', () async {
      final requests = _ProbeRequests((_) async => http.Response('', status));
      final storage = _Storage(requests);
      final file = File('draft-photo.jpg');
      var savedDrafts = 0;
      final controller = controllerFor(storage, [
        PhotoEntry.file(file, isMotion: true, uploadLive: true),
      ], onUploaded: () => savedDrafts++)..restore(file.path, _oldUrl, true);

      await controller.prepareForPublish();

      expect(requests.urls, [Uri.parse(_oldUrl)]);
      expect(storage.uploads, 1);
      expect(controller.uploadedUrls[file.path], _newUrl);
      expect(controller.uploadedIsLive[file.path], isTrue);
      expect(controller.statuses[file.path], PhotoUploadStatus.success);
      expect(savedDrafts, 1);
    });
  }

  test('reuses an existing original without uploading it again', () async {
    final requests = _ProbeRequests((_) async => http.Response('', 200));
    final storage = _Storage(requests);
    final file = File('draft-photo.jpg');
    final controller = controllerFor(storage, [PhotoEntry.file(file)])
      ..restore(file.path, _oldUrl, false);

    await controller.prepareForPublish();

    expect(storage.uploads, 0);
    expect(controller.uploadedUrls[file.path], _oldUrl);
  });

  for (final status in [401, 403, 429, 500]) {
    test(
      'HTTP $status stops publishing and retains the uploaded URL',
      () async {
        final requests = _ProbeRequests((_) async => http.Response('', status));
        final storage = _Storage(requests);
        final file = File('draft-photo.jpg');
        final controller = controllerFor(storage, [PhotoEntry.file(file)])
          ..restore(file.path, _oldUrl, false);

        await expectLater(controller.prepareForPublish(), throwsException);

        expect(storage.uploads, 0);
        expect(controller.uploadedUrls[file.path], _oldUrl);
      },
    );
  }

  test(
    'a network failure retains the draft upload for a later retry',
    () async {
      final requests = _ProbeRequests(
        (_) async => throw TimeoutException('offline'),
      );
      final storage = _Storage(requests);
      final file = File('draft-photo.jpg');
      final controller = controllerFor(storage, [PhotoEntry.file(file)])
        ..restore(file.path, _oldUrl, false);

      await expectLater(
        controller.prepareForPublish(),
        throwsA(isA<TimeoutException>()),
      );

      expect(storage.uploads, 0);
      expect(controller.uploadedUrls[file.path], _oldUrl);
    },
  );

  test('a failed replacement never leaves the stale URL publishable', () async {
    final requests = _ProbeRequests((_) async => http.Response('', 404));
    final storage = _Storage(requests)..failUpload = true;
    final file = File('draft-photo.jpg');
    final controller = controllerFor(storage, [PhotoEntry.file(file)])
      ..restore(file.path, _oldUrl, false);

    await controller.prepareForPublish();

    expect(storage.uploads, 1);
    expect(controller.uploadedUrls.containsKey(file.path), isFalse);
    expect(controller.statuses[file.path], PhotoUploadStatus.failed);
  });

  test('new local photos upload while remote entries stay untouched', () async {
    final requests = _ProbeRequests(
      (_) async => throw StateError('unexpected probe'),
    );
    final storage = _Storage(requests);
    final file = File('new-photo.jpg');
    final controller = controllerFor(storage, [
      PhotoEntry.file(file),
      const PhotoEntry.url(_oldUrl),
    ]);

    await controller.prepareForPublish();

    expect(storage.uploads, 1);
    expect(requests.urls, isEmpty);
    expect(controller.uploadedUrls[file.path], _newUrl);
  });

  test(
    'the probe uses the original URL and revalidates cached responses',
    () async {
      final requests = _ProbeRequests((_) async => http.Response('', 200));
      final storage = StorageService(http: requests);

      expect(
        await storage.originalExists('$_oldUrl?variant=preview&pv=1'),
        isTrue,
      );

      expect(requests.urls, [Uri.parse(_oldUrl)]);
      expect(requests.headers?['Cache-Control'], 'no-cache');
    },
  );
}
