import 'dart:io';

import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/services/draft_service.dart';
import 'package:diptych/services/shared_diary_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-shared-draft-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  test('draft keeps original motion bytes, photo order and revision across reopening', () async {
    final source = File('${temp.path}/original.jpg');
    final bytes = [
      255,
      216,
      255,
      217,
      ...'embedded-original-motion-video'.codeUnits,
    ];
    await source.writeAsBytes(bytes);
    final store = SharedDiaryDraftStore(userId: 'A', dateStr: '2026-10-29');
    final base = SharedMoment(
      id: 'day',
      dateStr: '2026-10-29',
      revision: 9,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      blocks: [SharedMomentBlock.text(id: 'text', authorId: 'A', text: '正文')],
    );
    final normal = MomentDraftStore(userId: 'A', dateStr: base.dateStr);
    await normal.save(feeling: '普通日记草稿', mood: 8, items: []);
    await store.save(
      SharedDiaryDraft(
        base: base,
        blocks: base.blocks,
        splits: [],
        photos: [
          SharedDraftPhoto(
            blockId: 'local',
            authorId: 'A',
            item: DraftPhotoItem(
              isLocal: true,
              file: source,
              isMotion: true,
              uploadLive: true,
              uploadedUrl: 'https://image.invalid/original.jpg',
              uploadedLive: true,
            ),
          ),
          const SharedDraftPhoto(
            blockId: 'remote',
            authorId: 'B',
            item: DraftPhotoItem(
              isLocal: false,
              url: 'https://image.invalid/b.jpg',
            ),
          ),
        ],
      ),
    );
    await source.delete();
    final restored = await SharedDiaryDraftStore(
      userId: 'A',
      dateStr: base.dateStr,
    ).load();
    expect(restored!.base.revision, 9);
    expect(restored.photos.map((p) => p.blockId), ['local', 'remote']);
    expect(await restored.photos.first.item.file!.readAsBytes(), bytes);
    expect(restored.photos.first.item.uploadLive, isTrue);
    expect(
      restored.photos.first.item.uploadedUrl,
      'https://image.invalid/original.jpg',
    );
    expect(
      await SharedDiaryDraftStore(userId: 'B', dateStr: base.dateStr).load(),
      isNull,
    );
    await store.clear();
    expect(await store.load(), isNull);
    expect((await normal.load())!.feeling, '普通日记草稿');
  });

  test(
    'missing local originals fail visibly without deleting the manifest',
    () async {
      final store = SharedDiaryDraftStore(userId: 'A', dateStr: '2026-10-29');
      final file = File('${temp.path}/p.jpg');
      await file.writeAsBytes([1, 2, 3]);
      final base = SharedMoment(
        id: 'day',
        dateStr: '2026-10-29',
        revision: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await store.save(
        SharedDiaryDraft(
          base: base,
          blocks: [],
          splits: [],
          photos: [
            SharedDraftPhoto(
              blockId: 'p',
              authorId: 'A',
              item: DraftPhotoItem(isLocal: true, file: file),
            ),
          ],
        ),
      );
      final restored = await store.load();
      await restored!.photos.first.item.file!.delete();
      await expectLater(store.load(), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getKeys().any(
          (key) => key.startsWith('shared_draft_'),
        ),
        isTrue,
      );
    },
  );
}
