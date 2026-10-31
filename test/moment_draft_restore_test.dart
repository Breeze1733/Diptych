import 'dart:convert';
import 'dart:io';

import 'package:diptych/models/app_user.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/screens/edit_moment_screen.dart';
import 'package:diptych/services/draft_service.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _date = '2026-10-31';
const _key = 'moment_draft_v2_A_$_date';
final _image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late MomentDraftStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-restore-test-');
    SharedPreferences.setMockInitialValues({});
    store = MomentDraftStore(userId: 'A', dateStr: _date);
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
    if (temp.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !temp.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('diptych-restore-test-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  Future<File> seedDraft({bool motion = true}) async {
    final source = File('${temp.path}/source.jpg');
    await source.writeAsBytes(_image);
    await store.save(
      feeling: '不能丢失的原稿',
      mood: 8,
      items: [
        DraftPhotoItem(
          isLocal: true,
          file: source,
          isMotion: motion,
          uploadLive: motion,
          uploadedUrl: 'https://images.invalid/original.jpg',
          uploadedLive: motion,
        ),
        const DraftPhotoItem(
          isLocal: false,
          url: 'https://images.invalid/remote.jpg',
        ),
      ],
    );
    return (await store.load())!.photoItems.first.file!;
  }

  test('missing original blocks overwrite and a complete retry restores the entire draft', () async {
    final file = await seedDraft();
    final prefs = await SharedPreferences.getInstance();
    final manifest = prefs.getString(_key);
    await file.delete();
    await expectLater(store.load(), throwsA(isA<DraftRestoreException>()));
    await expectLater(
      store.save(feeling: '覆盖内容', mood: null, items: []),
      throwsA(isA<DraftRestoreException>()),
    );
    expect(prefs.getString(_key), manifest);
    await file.writeAsBytes(_image);
    final recovered = (await store.load())!;
    expect(recovered.feeling, '不能丢失的原稿');
    expect(recovered.mood, 8);
    expect(recovered.photoItems, hasLength(2));
    expect(recovered.photoItems.first.uploadedLive, isTrue);
    expect(recovered.photoItems.last.url, 'https://images.invalid/remote.jpg');
    await store.save(
      feeling: '恢复后继续编辑',
      mood: recovered.mood,
      items: recovered.photoItems,
    );
    expect((await store.load())!.feeling, '恢复后继续编辑');
  });

  for (final invalid in [
    'corrupt json',
    'missing photo entry',
    'unsafe path',
  ]) {
    test('$invalid is reported without replacing the manifest', () async {
      await seedDraft();
      final prefs = await SharedPreferences.getInstance();
      final data = jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
      if (invalid == 'missing photo entry') data['items'] = [null];
      if (invalid == 'unsafe path') {
        (data['items'] as List).first['file_name'] = '../missing.jpg';
      }
      final raw = invalid == 'corrupt json' ? '{broken' : jsonEncode(data);
      await prefs.setString(_key, raw);
      await expectLater(store.load(), throwsA(isA<DraftRestoreException>()));
      await expectLater(
        store.save(feeling: '', mood: null, items: []),
        throwsA(isA<DraftRestoreException>()),
      );
      expect(prefs.getString(_key), raw);
    });
  }

  test('an owned legacy draft with missing photos is retained while other accounts ignore it', () async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode({
      'owner_id': 'A',
      'feeling': '旧草稿',
      'items': [
        {'type': 'local', 'local_index': 0},
      ],
    });
    await prefs.setString('draft_$_date', raw);
    await expectLater(store.load(), throwsA(isA<DraftRestoreException>()));
    expect(await MomentDraftStore(userId: 'B', dateStr: _date).load(), isNull);
    expect(prefs.getString('draft_$_date'), raw);
  });

  testWidgets(
    'failed restore disables writes, preserves the draft on exit and can be retried',
    (tester) async {
      final file = (await tester.runAsync(() => seedDraft(motion: false)))!;
      final prefs = await SharedPreferences.getInstance();
      final manifest = prefs.getString(_key);
      await tester.runAsync(file.delete);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(currentUserProvider.notifier)
          .setUser(const AppUser(uid: 'A', nickname: 'A', partnerUid: 'B'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          EditMomentScreen(date: DateTime(2026, 10, 31)),
                    ),
                  ),
                  child: const Text('打开编辑器'),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> waitFor(Finder target) async {
        for (var i = 0; i < 80; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (target.evaluate().isNotEmpty) return;
        }
        fail('Editor did not reach the expected restore state');
      }

      Future<void> openFailure() async {
        await tester.tap(find.text('打开编辑器'));
        await tester.pumpAndSettle();
        await waitFor(find.text('草稿恢复失败'));
      }

      await openFailure();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '存草稿'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '转共记'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发布'))
            .onPressed,
        isNull,
      );
      expect(find.byType(PhotoGridPicker), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EditMomentScreen), findsNothing);
      expect(prefs.getString(_key), manifest);
      await openFailure();
      await tester.runAsync(() => file.writeAsBytes(_image));
      await tester.tap(find.text('重试恢复'));
      await waitFor(find.byKey(const ValueKey('diary-feeling-input')));
      await tester.pumpAndSettle();
      expect(find.text('草稿恢复失败'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('diary-feeling-input')),
            )
            .controller!
            .text,
        '不能丢失的原稿',
      );
      expect(
        tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).entries,
        hasLength(2),
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '存草稿'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
