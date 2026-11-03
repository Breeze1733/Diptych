import 'dart:io';

import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/services/draft_service.dart';
import 'package:diptych/services/shared_diary_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/motion_photo_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-draft-mode-');
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (temp.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !temp.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('diptych-draft-mode-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  final base = SharedMoment(
    id: 'shared-day',
    dateStr: '2026-11-03',
    revision: 1,
    blocks: [],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  for (final shared in [false, true]) {
    for (final live in [false, true]) {
      test(
        '${shared ? 'shared' : 'normal'} draft restores the requested ${live ? 'live' : 'static'} bytes',
        () async {
          final source = File('${temp.path}/source.jpg');
          final original = croppedMotionPhoto();
          await source.writeAsBytes(original);
          final item = DraftPhotoItem(
            isLocal: true,
            file: source,
            // Static selection must be enforced even if detection missed it.
            isMotion: live,
            uploadLive: live,
            uploadedUrl: 'https://images.invalid/old.jpg',
            uploadedLive: live,
          );
          late DraftPhotoItem restored;
          final prefs = await SharedPreferences.getInstance();
          if (shared) {
            final store = SharedDiaryDraftStore(
              userId: 'A',
              dateStr: base.dateStr,
            );
            final draft = SharedDiaryDraft(
              base: base,
              blocks: [],
              splits: [],
              photos: [
                SharedDraftPhoto(blockId: 'photo', authorId: 'A', item: item),
              ],
            );
            await store.save(draft);
            await store.saveWorking(draft, publishAfterConflict: true);
            final manifest = prefs.getString(
              'shared_draft_v2_shared_A_${base.dateStr}',
            );
            expect(manifest, isNotNull);
            restored = (await store.load())!.photos.single.item;
            final working = (await store.loadWorking())!;
            expect(
              await working.draft.photos.single.item.file!.readAsBytes(),
              live ? original : jpegCover,
            );
            expect(working.publishAfterConflict, isTrue);
            expect(
              prefs.getString('shared_draft_v2_shared_A_${base.dateStr}'),
              manifest,
            );
          } else {
            final store = MomentDraftStore(userId: 'A', dateStr: base.dateStr);
            await store.save(feeling: '正文', mood: 8, items: [item]);
            final manifest = prefs.getString(
              'moment_draft_v2_A_${base.dateStr}',
            );
            final draft = (await store.load())!;
            expect(draft.feeling, '正文');
            expect(draft.mood, 8);
            restored = draft.photoItems.single;
            expect(
              prefs.getString('moment_draft_v2_A_${base.dateStr}'),
              manifest,
            );
          }
          expect(
            await restored.file!.readAsBytes(),
            live ? original : jpegCover,
          );
          expect(restored.uploadLive, live);
          expect(restored.uploadedUrl, live ? item.uploadedUrl : isNull);
          expect(await source.readAsBytes(), original);
        },
      );
    }
  }

  test(
    'an unchanged static draft reuses its uploaded URL and stable file',
    () async {
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes(jpegCover);
      final store = MomentDraftStore(userId: 'A', dateStr: base.dateStr);
      await store.save(
        feeling: '',
        mood: null,
        items: [
          DraftPhotoItem(
            isLocal: true,
            file: source,
            uploadedUrl: 'https://images.invalid/still.jpg',
            uploadedLive: false,
          ),
        ],
      );
      final first = (await store.load())!.photoItems.single;
      final second = (await store.load())!.photoItems.single;
      expect(second.file!.path, first.file!.path);
      expect(second.uploadedUrl, first.uploadedUrl);
      expect(second.uploadedUrl, isNotNull);
    },
  );
}
