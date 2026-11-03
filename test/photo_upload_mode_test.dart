import 'dart:io';

import 'package:diptych/models/app_user.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/screens/edit_moment_screen.dart';
import 'package:diptych/screens/shared_diary_editor_screen.dart';
import 'package:diptych/services/storage_service.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/motion_photo_fixture.dart';

class _RecordingStorage extends StorageService {
  final uploaded = <List<int>>[];

  @override
  Future<String> uploadImage(
    File file,
    String folder, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
    void Function(String)? onUploadIdCreated,
  }) async {
    uploaded.add(await file.readAsBytes());
    return 'https://images.invalid/upload.jpg';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diptych-upload-mode-');
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'plugins.flutter.io/path_provider',
      'com.splitmoments.split_moments/foreground_service',
      'com.splitmoments.split_moments/wakelock',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => temp.path,
      );
    }
  });
  tearDown(() async {
    for (final channel in [
      'plugins.flutter.io/path_provider',
      'com.splitmoments.split_moments/foreground_service',
      'com.splitmoments.split_moments/wakelock',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    if (temp.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !temp.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('diptych-upload-mode-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  Future<void> waitFor(WidgetTester tester, bool Function() predicate) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (predicate()) return;
    }
    fail('Editor did not finish photo preparation');
  }

  for (final shared in [false, true]) {
    for (final mode in ['static', 'undetected motion', 'live']) {
      testWidgets(
        '${shared ? 'shared' : 'normal'} editor uploads requested $mode bytes',
        (tester) async {
          final storage = _RecordingStorage();
          final container = ProviderContainer(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
          );
          addTearDown(container.dispose);
          container
              .read(currentUserProvider.notifier)
              .setUser(const AppUser(uid: 'A', nickname: 'A', partnerUid: 'B'));
          final source = File('${temp.path}/edited.jpg');
          final original = croppedMotionPhoto();
          await tester.runAsync(() => source.writeAsBytes(original));
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: shared
                    ? SharedDiaryEditorScreen(
                        initialMoment: SharedMoment(
                          id: 'day',
                          dateStr: '2026-11-03',
                          revision: 1,
                          blocks: [],
                          createdAt: DateTime(2026),
                          updatedAt: DateTime(2026),
                        ),
                      )
                    : EditMomentScreen(date: DateTime(2026, 11, 3)),
              ),
            ),
          );
          await waitFor(
            tester,
            () => find.byType(PhotoGridPicker).evaluate().isNotEmpty,
          );
          final live = mode == 'live';
          tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).onAdded([
            PhotoEntry.file(
              source,
              isMotion: mode != 'undetected motion',
              uploadLive: live,
            ),
          ]);
          await waitFor(tester, () => storage.uploaded.isNotEmpty);
          if (!shared) {
            final prefs = await SharedPreferences.getInstance();
            await waitFor(
              tester,
              () =>
                  prefs
                      .getString('moment_draft_v2_A_2026-11-03')
                      ?.contains('https://images.invalid/upload.jpg') ==
                  true,
            );
          }
          expect(storage.uploaded.single, live ? original : jpegCover);
          final entry = tester
              .widget<PhotoGridPicker>(find.byType(PhotoGridPicker))
              .entries
              .single;
          expect(entry.uploadLive, live);
          expect(entry.isMotion, live);
          expect(await tester.runAsync(source.readAsBytes), original);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
