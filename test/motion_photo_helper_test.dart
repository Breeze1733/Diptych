import 'dart:io';

import 'package:diptych/utils/motion_photo_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/motion_photo_fixture.dart';

void main() {
  late Directory temp;
  late File source;
  late File destination;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-motion-test-');
    source = File('${temp.path}/source.jpg');
    destination = File('${temp.path}/still.jpg');
  });
  tearDown(() async {
    if (temp.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !temp.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('diptych-motion-test-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  for (final padding in [0, 300 * 1024]) {
    test(
      'removes every embedded video after an edited cover ($padding)',
      () async {
        final original = croppedMotionPhoto(padding: padding);
        await source.writeAsBytes(original);
        final still = await MotionPhotoHelper.extractStillImageTo(
          source,
          destination,
        );
        expect(still.path, destination.path);
        expect(await still.readAsBytes(), jpegCover);
        expect(await MotionPhotoHelper.isMotionPhoto(still), isFalse);
        expect(await source.readAsBytes(), original);
      },
    );
  }

  test(
    'small motion files remain detectable when live upload is selected',
    () async {
      await source.writeAsBytes([...jpegCover, ...mp4Payload()]);
      expect(await MotionPhotoHelper.isMotionPhoto(source), isTrue);
    },
  );

  test(
    'metadata thumbnails and ftyp bytes do not truncate the cover',
    () async {
      final metadata = [0xff, 0xd8, 0xff, 0xd9, ...mp4Payload()];
      final length = metadata.length + 2;
      final image = [
        ...jpegCover.take(2),
        0xff,
        0xe1,
        length >> 8,
        length & 255,
        ...metadata,
        ...jpegCover.skip(2),
      ];
      await source.writeAsBytes([...image, ...mp4Payload(padding: 110 * 1024)]);
      await MotionPhotoHelper.extractStillImageTo(source, destination);
      expect(await destination.readAsBytes(), image);
    },
  );

  test(
    'retains auxiliary images before the video without reencoding',
    () async {
      final stillBytes = [...jpegCover, ...jpegCover];
      await source.writeAsBytes([
        ...stillBytes,
        ...mp4Payload(padding: 110 * 1024),
      ]);
      await MotionPhotoHelper.extractStillImageTo(source, destination);
      expect(await destination.readAsBytes(), stillBytes);
    },
  );

  test('handles progressive scans, escaped bytes and split markers', () async {
    final image = [
      0xff, 0xd8,
      0xff, 0xda, 0, 2,
      // Put the first marker prefix at the end of a 256 KB scan block.
      ...List.filled(256 * 1024 - 1, 1),
      0xff, 0xc4, 0, 2,
      0xff, 0xda, 0, 2,
      1, 0xff, 0, 0xd9, 0xff, 0xd0, 2, 0xff, 0xff, 0xd9,
    ];
    await source.writeAsBytes([...image, ...mp4Payload()]);
    await MotionPhotoHelper.extractStillImageTo(source, destination);
    expect(await destination.readAsBytes(), image);
  });

  test('finds the first MP4 header across search block boundaries', () async {
    for (var split = 1; split < 8; split++) {
      final padding = 256 * 1024 - 64 - jpegCover.length + 8 + split;
      await source.writeAsBytes(croppedMotionPhoto(padding: padding));
      await MotionPhotoHelper.extractStillImageTo(source, destination);
      expect(
        await destination.readAsBytes(),
        jpegCover,
        reason: 'split $split',
      );
    }
  });

  test('overwrites a stale destination even when its length matches', () async {
    await source.writeAsBytes([
      ...jpegCover,
      ...mp4Payload(padding: 110 * 1024),
    ]);
    await destination.writeAsBytes(List.filled(jpegCover.length, 0));
    await MotionPhotoHelper.extractStillImageTo(source, destination);
    expect(await destination.readAsBytes(), jpegCover);
  });

  test('unchanged static JPEG and non-JPEG bytes are copied exactly', () async {
    for (final bytes in [
      jpegCover,
      [0x89, 0x50, 0x4e, 0x47, 1, 2, 3],
    ]) {
      await source.writeAsBytes(bytes);
      await MotionPhotoHelper.extractStillImageTo(source, destination);
      expect(await destination.readAsBytes(), bytes);
    }
  });

  test('missing input and malformed JPEG fail without falling back to the original', () async {
    await expectLater(
      MotionPhotoHelper.extractStillImageTo(source, destination),
      throwsA(isA<FileSystemException>()),
    );
    await source.writeAsBytes([0xff, 0xd8, 0xff, 0xe1, 0x7f, 0xff]);
    await expectLater(
      MotionPhotoHelper.extractStillImageTo(source, destination),
      throwsA(isA<FormatException>()),
    );
    expect(await destination.exists(), isFalse);
  });

  test('refuses to overwrite the original during extraction', () async {
    final original = croppedMotionPhoto();
    await source.writeAsBytes(original);
    await expectLater(
      MotionPhotoHelper.extractStillImageTo(source, source),
      throwsArgumentError,
    );
    expect(await source.readAsBytes(), original);
  });

  test('a write failure is reported and leaves the source intact', () async {
    final original = croppedMotionPhoto();
    await source.writeAsBytes(original);
    await File('${temp.path}/not-a-directory').writeAsString('block');
    await expectLater(
      MotionPhotoHelper.extractStillImageTo(
        source,
        File('${temp.path}/not-a-directory/still.jpg'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.readAsBytes(), original);
  });
}
