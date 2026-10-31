import 'dart:async';
import 'dart:io';

import 'package:diptych/models/app_user.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/providers/shared_diary_draft_provider.dart';
import 'package:diptych/screens/shared_diary_editor_screen.dart';
import 'package:diptych/screens/shared_diary_reading_screen.dart';
import 'package:diptych/services/api_service.dart';
import 'package:diptych/services/draft_service.dart';
import 'package:diptych/services/shared_diary_draft.dart';
import 'package:diptych/services/storage_service.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:diptych/widgets/shared_diary_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String documentText(Iterable<SharedMomentBlock> blocks) => blocks
    .where((b) => b.type == SharedMomentBlockType.text)
    .map((b) => b.text)
    .join();

SharedMoment day() => SharedMoment(
  id: 'day',
  dateStr: '2026-10-29',
  revision: 2,
  blocks: [
    SharedMomentBlock.text(id: 'text', authorId: 'A', text: '原文'),
    SharedMomentBlock.image(
      id: 'old-photo',
      authorId: 'A',
      imageUrl: 'https://images.invalid/old.jpg',
    ),
    SharedMomentBlock.image(
      id: 'partner-photo',
      authorId: 'B',
      imageUrl: 'https://images.invalid/b.jpg',
    ),
  ],
  createdAt: DateTime(2026, 10, 29),
  updatedAt: DateTime(2026, 10, 29),
);

class MemoryDraft extends SharedDiaryDraftStore {
  SharedDiaryDraft? value;
  SharedDiaryWorkingDraft? working;
  int saves = 0;
  int? failAtRevision;
  Object? loadFailure;
  MemoryDraft() : super(userId: 'A', dateStr: '2026-10-29');
  @override
  Future<SharedDiaryDraft?> load() async {
    if (loadFailure != null) throw loadFailure!;
    return value;
  }

  @override
  Future<void> save(SharedDiaryDraft draft) async {
    if (draft.base.revision == failAtRevision) throw StateError('本地存储失败');
    value = draft;
    saves++;
  }

  @override
  Future<SharedDiaryWorkingDraft?> loadWorking() async => working;

  @override
  Future<void> saveWorking(
    SharedDiaryDraft draft, {
    required bool publishAfterConflict,
  }) async {
    working = SharedDiaryWorkingDraft(
      draft: draft,
      publishAfterConflict: publishAfterConflict,
    );
  }

  @override
  Future<void> clearWorking() async {
    working = null;
  }

  @override
  Future<void> clear() async {
    value = null;
    working = null;
  }

  @override
  Future<File> importImage(File file) async => file;
}

class PendingStorage extends StorageService {
  final pending = Completer<String>();
  int probes = 0;
  int uploads = 0;
  Object? probeFailure;
  @override
  Future<String> uploadImage(
    File file,
    String folder, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
    void Function(String)? onUploadIdCreated,
  }) {
    uploads++;
    return pending.future;
  }

  @override
  Future<bool> originalExists(String url) async {
    probes++;
    if (probeFailure != null) throw probeFailure!;
    return true;
  }
}

class RecordingApi extends ApiService {
  final calls = <List<SharedMomentBlock>>[];
  final revisions = <int>[];
  SharedMoment? conflict;
  SharedMoment? readingMoment;
  Object? failure;
  @override
  Future<SharedMoment> getSharedMomentById(String id) async =>
      readingMoment ?? day();
  @override
  Future<SharedMoment> updateSharedMoment({
    required SharedMoment moment,
    required List<SharedMomentBlock> blocks,
    List<Map<String, dynamic>> splitForeignText = const [],
  }) async {
    calls.add(List.of(blocks));
    revisions.add(moment.revision);
    if (conflict != null) {
      final latest = conflict!;
      conflict = null;
      throw SharedMomentConflictException(latest: latest);
    }
    if (failure != null) throw failure!;
    return moment.copyWith(
      blocks: List.of(blocks),
      revision: moment.revision + 1,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
      addTearDown(
        () => messenger.setMockMethodCallHandler(MethodChannel(channel), null),
      );
    }
  });

  Future<void> pumpEditor(
    WidgetTester tester,
    MemoryDraft draft,
    PendingStorage storage,
    RecordingApi api, {
    bool pushRoute = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedDiaryDraftStoreProvider.overrideWith((ref, scope) => draft),
        storageServiceProvider.overrideWithValue(storage),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentUserProvider.notifier)
        .setUser(const AppUser(uid: 'A', nickname: 'A', partnerUid: 'B'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: pushRoute
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SharedDiaryEditorScreen(initialMoment: day()),
                        ),
                      ),
                      child: const Text('打开共记'),
                    ),
                  ),
                )
              : SharedDiaryEditorScreen(initialMoment: day()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (pushRoute) {
      await tester.tap(find.text('打开共记'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> addPhoto(WidgetTester tester) async {
    tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).onAdded([
      PhotoEntry.file(
        File('motion-original.jpg'),
        isMotion: true,
        uploadLive: true,
      ),
    ]);
    await tester.pumpAndSettle();
  }

  Future<TextEditingController> editorText(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('shared-continuous-text-editor')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  Future<void> editText(WidgetTester tester, String text) async {
    (await editorText(tester)).text = text;
    await tester.pump();
  }

  Future<void> waitForPublication(
    WidgetTester tester,
    MemoryDraft draft,
  ) async {
    // Original-cache promotion performs real file IO outside the widget clock.
    for (var attempt = 0; attempt < 100 && draft.value != null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      draft.value,
      isNull,
      reason: 'Publication must finish before asserting its result',
    );
  }

  SharedMoment remoteText(int revision, String text) => day().copyWith(
    revision: revision,
    blocks: [
      day().blocks.first.copyWith(text: text),
      ...day().blocks.skip(1),
    ],
  );

  testWidgets(
    'reverted saved text stays reverted after leaving and reopening',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api, pushRoute: true);
      await editText(tester, '原文曾经添加的内容');
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      expect(documentText(draft.value!.blocks), '原文曾经添加的内容');
      await editText(tester, '原文');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SharedDiaryEditorScreen), findsNothing);
      await tester.tap(find.text('打开共记'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '原文');
    },
  );

  testWidgets('removed imported photos stay removed after an unchanged exit', (
    tester,
  ) async {
    final draft = MemoryDraft(),
        storage = PendingStorage(),
        api = RecordingApi();
    await pumpEditor(tester, draft, storage, api, pushRoute: true);
    await addPhoto(tester);
    expect(draft.value!.photos, hasLength(3));
    tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).onRemoved(2);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SharedDiaryEditorScreen), findsNothing);
    await tester.tap(find.text('打开共记'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).entries,
      hasLength(2),
    );
    expect(storage.uploads, 1);
  });

  testWidgets(
    'an unchanged exit preserves the recoverable conflict workspace',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      final base = day();
      draft.value = SharedDiaryDraft(
        base: base,
        blocks: base.blocks,
        splits: [],
        photos: [
          for (final b in base.blocks.where(
            (b) => b.type == SharedMomentBlockType.image,
          ))
            SharedDraftPhoto(
              blockId: b.id,
              authorId: b.authorId,
              item: DraftPhotoItem(isLocal: false, url: b.imageUrl),
            ),
        ],
      );
      final working = SharedDiaryWorkingDraft(
        draft: SharedDiaryDraft(
          base: base,
          blocks: [base.blocks.first.copyWith(text: '尚未确认的二次编辑')],
          splits: [],
          photos: [],
        ),
        publishAfterConflict: false,
      );
      draft.working = working;
      await pumpEditor(tester, draft, storage, api, pushRoute: true);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(identical(draft.working, working), isTrue);
      await tester.tap(find.text('打开共记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续上次二次编辑'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '尚未确认的二次编辑');
    },
  );

  testWidgets('failed draft sync keeps an unchanged editor open for retry', (
    tester,
  ) async {
    final draft = MemoryDraft(),
        storage = PendingStorage(),
        api = RecordingApi();
    await pumpEditor(tester, draft, storage, api, pushRoute: true);
    await editText(tester, '原文曾经添加的内容');
    await tester.tap(find.text('存草稿'));
    await tester.pumpAndSettle();
    await editText(tester, '原文');
    draft.failAtRevision = 2;
    // Let the earlier successful-save notification finish before the error.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SharedDiaryEditorScreen), findsOneWidget);
    expect(find.textContaining('本地存储失败'), findsOneWidget);
    draft.failAtRevision = null;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SharedDiaryEditorScreen), findsNothing);
    expect(documentText(draft.value!.blocks), '原文');
  });

  testWidgets('an unreadable draft is preserved when leaving without edits', (
    tester,
  ) async {
    final draft = MemoryDraft(),
        storage = PendingStorage(),
        api = RecordingApi();
    final saved = SharedDiaryDraft(
      base: day(),
      blocks: [day().blocks.first.copyWith(text: '无法恢复但不能覆盖的草稿')],
      splits: [],
      photos: [],
    );
    draft.value = saved;
    draft.loadFailure = StateError('本地照片缺失');
    await pumpEditor(tester, draft, storage, api, pushRoute: true);
    expect(find.textContaining('本地照片缺失'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SharedDiaryEditorScreen), findsNothing);
    expect(identical(draft.value, saved), isTrue);
    expect(draft.saves, 0);
  });

  testWidgets(
    'draft and text updates stay open and never wait for pending photos',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api);
      await addPhoto(tester);
      final picker = tester.widget<PhotoGridPicker>(
        find.byType(PhotoGridPicker),
      );
      picker.onRemoved(
        0,
      ); // Pending deletion must not reach the text-only request.
      await tester.pump();
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      expect(draft.value!.photos, hasLength(2));
      expect(storage.pending.isCompleted, isFalse);
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
      expect(
        api.calls.single
            .where((b) => b.type == SharedMomentBlockType.image)
            .map((b) => b.id),
        ['old-photo', 'partner-photo'],
      );
      expect(storage.probes, 0);
      expect(storage.pending.isCompleted, isFalse);
      expect(find.byType(SharedDiaryEditorScreen), findsOneWidget);
      expect(
        tester.widget<PhotoGridPicker>(find.byType(PhotoGridPicker)).entries,
        hasLength(2),
      );
      expect(draft.value!.base.revision, 3);
      expect(draft.value!.photos.last.item.uploadLive, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'reopening resumes a saved local photo with its original block identity',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      final base = day();
      draft.value = SharedDiaryDraft(
        base: base,
        blocks: [
          ...base.blocks,
          SharedMomentBlock.image(id: 'pending', authorId: 'A', imageUrl: ''),
        ],
        splits: [],
        photos: [
          for (final b in base.blocks.where(
            (b) => b.type == SharedMomentBlockType.image,
          ))
            SharedDraftPhoto(
              blockId: b.id,
              authorId: b.authorId,
              item: DraftPhotoItem(isLocal: false, url: b.imageUrl),
            ),
          SharedDraftPhoto(
            blockId: 'pending',
            authorId: 'A',
            item: DraftPhotoItem(
              isLocal: true,
              file: File('motion-original.jpg'),
              isMotion: true,
              uploadLive: true,
            ),
          ),
        ],
      );
      await pumpEditor(tester, draft, storage, api);
      expect(storage.uploads, 1);
      expect(
        tester
            .widget<PhotoGridPicker>(find.byType(PhotoGridPicker))
            .entries
            .last
            .uploadLive,
        isTrue,
      );
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      expect(draft.value!.photos.last.blockId, 'pending');
      expect(draft.value!.blocks.last.id, 'pending');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'conflict rebase preserves local photo while its upload continues',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      api.conflict = day().copyWith(
        revision: 3,
        blocks: [
          ...day().blocks,
          SharedMomentBlock.text(
            id: 'partner-text',
            authorId: 'B',
            text: '新文字',
          ),
        ],
      );
      await pumpEditor(tester, draft, storage, api);
      await addPhoto(tester);
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉取最新并二次编辑'));
      await tester.pumpAndSettle();
      expect(storage.uploads, 1);
      expect(storage.pending.isCompleted, isFalse);
      expect(draft.value!.photos.last.item.file!.path, 'motion-original.jpg');
      expect(
        draft.working!.draft.blocks
            .where((b) => b.type == SharedMomentBlockType.text)
            .map((b) => b.text),
        ['原文', '新文字'],
      );
      expect(draft.value!.base.revision, 2);
      expect(
        draft.value!.blocks
            .where((b) => b.type == SharedMomentBlockType.text)
            .map((b) => b.text),
        ['原文'],
      );
      expect(draft.working!.draft.base.revision, 3);
      expect(draft.working!.publishAfterConflict, isFalse);
      expect(find.text('确认更新文字'), findsOneWidget);
      await tester.tap(find.text('确认更新文字'));
      await tester.pumpAndSettle();
      expect(find.text('更新文字'), findsOneWidget);
      expect(draft.value!.base.revision, 4);
      expect(documentText(draft.value!.blocks), '原文新文字');
      expect(draft.working, isNull);
      expect(draft.value!.photos.last.item.uploadLive, isTrue);
      expect(storage.pending.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('successful full publication clears the durable draft', (
    tester,
  ) async {
    final draft = MemoryDraft(),
        storage = PendingStorage(),
        api = RecordingApi();
    await pumpEditor(tester, draft, storage, api);
    await addPhoto(tester);
    storage.pending.complete('https://images.invalid/new.jpg');
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传发布'));
    await tester.pumpAndSettle();
    await waitForPublication(tester, draft);
    expect(api.calls, hasLength(1));
    expect(
      api.calls.single.where((b) => b.type == SharedMomentBlockType.image),
      hasLength(3),
    );
    expect(draft.value, isNull);
    expect(draft.saves, greaterThanOrEqualTo(3));
  });

  testWidgets(
    'each confirmation preserves the resolved draft and success advances the editing base',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api);
      await editText(tester, '原文本地原稿');
      api.conflict = remoteText(3, '原文远端第一次修改');
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉取最新并二次编辑'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '原文远端第一次修改');
      expect(documentText(draft.value!.blocks), '原文本地原稿');
      expect(draft.value!.base.revision, 2);
      expect(documentText(draft.working!.draft.reference!.blocks), '原文本地原稿');
      await editText(tester, '原文二次编辑补充');
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      api.conflict = remoteText(4, '原文远端再次修改');
      await tester.tap(find.text('确认更新文字'));
      await tester.pumpAndSettle();
      expect(find.text('更新文字'), findsOneWidget);
      expect((await editorText(tester)).text, '原文二次编辑补充');
      expect(documentText(draft.value!.blocks), '原文二次编辑补充');
      expect(draft.value!.base.revision, 3);
      await tester.tap(find.text('拉取最新并二次编辑'));
      await tester.pumpAndSettle();
      expect(documentText(draft.working!.draft.reference!.blocks), '原文二次编辑补充');
      await editText(tester, '原文核对完成');
      await tester.tap(find.text('确认更新文字'));
      await tester.pumpAndSettle();
      expect(find.text('更新文字'), findsOneWidget);
      expect(documentText(draft.value!.blocks), '原文核对完成');
      expect(draft.value!.base.revision, 5);
      expect(draft.working, isNull);
      expect(api.revisions, [2, 3, 4]);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await pumpEditor(tester, draft, storage, api);
      expect((await editorText(tester)).text, '原文核对完成');
      expect(find.text('继续上次二次编辑'), findsNothing);
      await editText(tester, '原文核对完成后继续编辑');
      api.failure = StateError('网络失败');
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '原文核对完成后继续编辑');
      expect(find.text('更新文字'), findsOneWidget);
      expect(documentText(draft.value!.blocks), '原文核对完成后继续编辑');
      expect(draft.value!.base.revision, 5);
      expect(api.revisions.last, 5);
      api.failure = null;
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      expect(draft.value!.base.revision, 6);
    },
  );

  testWidgets(
    'publication conflict confirmation clears both drafts and exits the entire editor',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api, pushRoute: true);
      await editText(tester, '发布前的本地原稿');
      await addPhoto(tester);
      storage.pending.complete('https://images.invalid/new.jpg');
      await tester.pumpAndSettle();
      api.conflict = remoteText(3, '另一端改了文字');
      await tester.tap(find.text('上传发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉取最新并二次编辑'));
      await tester.pumpAndSettle();
      expect(find.text('确认上传发布'), findsOneWidget);
      expect(documentText(draft.value!.blocks), '发布前的本地原稿');
      expect(draft.working!.publishAfterConflict, isTrue);
      await editText(tester, '核对后发布');
      await tester.tap(find.text('确认上传发布'));
      await tester.pumpAndSettle();
      await waitForPublication(tester, draft);
      expect(api.calls, hasLength(2));
      expect(
        api.calls.last.where((b) => b.type == SharedMomentBlockType.image),
        hasLength(3),
      );
      expect(draft.value, isNull);
      expect(draft.working, isNull);
      expect(find.byType(SharedDiaryEditorScreen), findsNothing);
      expect(find.text('打开共记'), findsOneWidget);
    },
  );

  testWidgets(
    'reopening and background uploads cannot overwrite an existing merge workspace',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api);
      await addPhoto(tester);
      api.conflict = remoteText(3, '原文对方补充');
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉取最新并二次编辑'));
      await tester.pumpAndSettle();
      await editText(tester, '原文二次编辑未提交');
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      final working = draft.working;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final resumedStorage = PendingStorage();
      await pumpEditor(tester, draft, resumedStorage, api);
      expect((await editorText(tester)).text, '原文');
      resumedStorage.pending.complete('https://images.invalid/resumed.jpg');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('拉取最新共记'), findsNothing);
      await tester.tap(find.text('存草稿'));
      await tester.pumpAndSettle();
      expect(documentText(draft.value!.blocks), '原文');
      expect(
        draft.value!.photos.last.item.uploadedUrl,
        'https://images.invalid/resumed.jpg',
      );
      expect(identical(draft.working, working), isTrue);
      await tester.tap(find.text('继续上次二次编辑'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '原文二次编辑未提交');
      await tester.tap(find.text('返回编辑'));
      await tester.pumpAndSettle();
      expect(find.text('更新文字'), findsOneWidget);
      expect(documentText(draft.value!.blocks), '原文二次编辑未提交');
      expect(draft.value!.base.revision, 3);
      expect(draft.working, isNull);
    },
  );

  testWidgets(
    'an accepted update keeps the latest server base even if local persistence then fails',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      await pumpEditor(tester, draft, storage, api);
      await editText(tester, '原文更新内容');
      draft.failAtRevision = 3;
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      expect((await editorText(tester)).text, '原文更新内容');
      expect(find.textContaining('内容已更新到最新版，但本地草稿处理失败'), findsOneWidget);
      draft.failAtRevision = null;
      await tester.tap(find.text('更新文字'));
      await tester.pumpAndSettle();
      expect(api.revisions, [2, 3]);
      expect(draft.value!.base.revision, 4);
      expect(documentText(draft.value!.blocks), '原文更新内容');
    },
  );

  for (final uploadFailure in [false, true]) {
    testWidgets(
      'second publication ${uploadFailure ? 'upload' : 'network'} failure restores the conflict-resolved submission copy',
      (tester) async {
        final draft = MemoryDraft(),
            storage = PendingStorage(),
            api = RecordingApi();
        await pumpEditor(tester, draft, storage, api);
        await editText(tester, '不能丢的本地原稿');
        await addPhoto(tester);
        storage.pending.complete('https://images.invalid/new.jpg');
        await tester.pumpAndSettle();
        api.conflict = remoteText(3, '远端文字');
        await tester.tap(find.text('上传发布'));
        await tester.pumpAndSettle();
        final original = draft.value!;
        await tester.tap(find.text('拉取最新并二次编辑'));
        await tester.pumpAndSettle();
        await editText(tester, '二次编辑后也不能丢');
        tester
            .widget<PhotoGridPicker>(find.byType(PhotoGridPicker))
            .onReordered(2, 0);
        await tester.pump();
        if (uploadFailure) {
          storage.probeFailure = StateError('照片暂时无法上传');
        } else {
          api.failure = const HandshakeException(
            'Connection terminated during handshake',
          );
        }
        await tester.tap(find.text('确认上传发布'));
        await tester.pumpAndSettle();
        expect(find.text('确认上传发布'), findsNothing);
        expect(find.text('上传发布'), findsOneWidget);
        expect(find.byType(SharedDiaryEditorScreen), findsOneWidget);
        expect((await editorText(tester)).text, '二次编辑后也不能丢');
        expect(documentText(draft.value!.blocks), '二次编辑后也不能丢');
        expect(draft.value!.base.revision, 3);
        expect(draft.value!.photos.map((p) => p.blockId), [
          original.photos.last.blockId,
          ...original.photos.take(2).map((p) => p.blockId),
        ]);
        expect(draft.value!.photos.first.item.uploadLive, isTrue);
        expect(draft.working, isNull);
        expect(
          draft.value!.photos.first.item.uploadedUrl,
          'https://images.invalid/new.jpg',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await pumpEditor(tester, draft, storage, api);
        expect((await editorText(tester)).text, '二次编辑后也不能丢');
        expect(find.text('继续上次二次编辑'), findsNothing);
      },
    );
  }

  testWidgets('shared reading photos expand to all rows and collapse', (
    tester,
  ) async {
    final moment = day().copyWith(
      blocks: [
        for (var i = 0; i < 12; i++)
          SharedMomentBlock.image(
            id: 'p$i',
            authorId: 'A',
            imageUrl: 'https://images.invalid/$i.jpg',
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(
            RecordingApi()..readingMoment = moment,
          ),
        ],
        child: MaterialApp(
          home: SharedDiaryReadingScreen(initialMoment: moment),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = find.byType(GridView);
    final collapsed = tester.getSize(grid).height;
    final expand = find.byTooltip('展开图片列表');
    final refresh = find.byTooltip('刷新共记');
    expect(
      find.descendant(of: find.byType(AppBar), matching: expand),
      findsOneWidget,
    );
    expect(tester.getSize(expand).width, lessThanOrEqualTo(48));
    expect(
      tester.getCenter(expand).dy,
      closeTo(tester.getCenter(refresh).dy, .01),
    );
    await tester.drag(grid, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller!.offset, greaterThan(0));
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(tester.getSize(grid).height, greaterThan(collapsed * 1.8));
    await tester.tap(find.byTooltip('收起图片列表'));
    await tester.pumpAndSettle();
    expect(tester.getSize(grid).height, collapsed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SharedDiaryDocument(moment: moment, compact: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开图片列表'), findsNothing);
    expect(find.text('展开图片列表'), findsNothing);
    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets(
    'shared editor keeps two locally scrolling rows without expansion or refresh controls',
    (tester) async {
      final draft = MemoryDraft(),
          storage = PendingStorage(),
          api = RecordingApi();
      final moment = day().copyWith(
        blocks: [
          for (var i = 0; i < 12; i++)
            SharedMomentBlock.image(
              id: 'photo-$i',
              authorId: 'A',
              imageUrl: 'https://images.invalid/$i.jpg',
            ),
        ],
      );
      draft.value = SharedDiaryDraft(
        base: moment,
        blocks: moment.blocks,
        splits: [],
        photos: [
          for (final block in moment.blocks)
            SharedDraftPhoto(
              blockId: block.id,
              authorId: block.authorId,
              item: DraftPhotoItem(isLocal: false, url: block.imageUrl),
            ),
        ],
      );
      await pumpEditor(tester, draft, storage, api);
      expect(
        tester
            .widget<PhotoGridPicker>(find.byType(PhotoGridPicker))
            .visibleRows,
        2,
      );
      expect(find.byTooltip('展开图片列表'), findsNothing);
      expect(find.text('展开图片列表'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      final grid = find.byKey(const ValueKey('diary-photo-grid'));
      expect(
        tester.widget<GridView>(grid).physics,
        isA<ClampingScrollPhysics>(),
      );
      await tester.drag(grid, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.widget<GridView>(grid).controller!.offset, greaterThan(0));
    },
  );

  testWidgets(
    'long press at collapsed grid edge scrolls beyond the first six photos',
    (tester) async {
      final entries = [
        for (var i = 0; i < 24; i++)
          PhotoEntry.url('https://images.invalid/$i.jpg'),
      ];
      int? movedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 215,
              child: PhotoGridPicker(
                entries: entries,
                visibleRows: 2,
                onAdded: (_) {},
                onRemoved: (_) {},
                onReordered: (oldIndex, newIndex) {
                  movedTo = newIndex;
                },
              ),
            ),
          ),
        ),
      );
      final grid = find.byKey(const ValueKey('diary-photo-grid'));
      final box = tester.getRect(grid);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo-slot-0'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(Offset(box.center.dx, box.bottom - 4));
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        tester.widget<GridView>(grid).controller!.offset,
        greaterThan(150),
      );
      final visibleTargets = find.byWidgetPredicate(
        (w) => w is DragTarget<int>,
      );
      expect(visibleTargets, findsWidgets);
      // Move a little to let the drag target hit-test the newly revealed row.
      await gesture.moveBy(const Offset(10, -12));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(movedTo, isNotNull);
      expect(movedTo!, greaterThan(5));
    },
  );
}
