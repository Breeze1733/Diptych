import 'dart:async';
import 'dart:io';

import 'package:diptych/constants/app_theme.dart';
import 'package:diptych/controllers/shared_document_text_controller.dart';
import 'package:diptych/models/app_user.dart';
import 'package:diptych/models/calendar_marked_dates.dart';
import 'package:diptych/models/moment.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/providers/day_moment_provider.dart';
import 'package:diptych/providers/wallpaper_provider.dart';
import 'package:diptych/screens/feed_screen.dart';
import 'package:diptych/screens/shared_diary_editor_screen.dart';
import 'package:diptych/screens/shared_diary_reading_screen.dart';
import 'package:diptych/services/api_service.dart';
import 'package:diptych/widgets/avatar_widget.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:diptych/widgets/shared_day_view.dart';
import 'package:diptych/widgets/shared_diary_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _userA = AppUser(uid: 'A', nickname: 'Alice', partnerUid: 'B');
const _userB = AppUser(uid: 'B', nickname: 'Bob', partnerUid: 'A');

SharedMoment _sharedMoment({List<SharedMomentBlock>? blocks}) {
  final timestamp = DateTime(2025, 6, 18, 12);
  return SharedMoment(
    id: 'shared-1',
    dateStr: '2025-06-18',
    revision: 3,
    blocks:
        blocks ??
        [
          SharedMomentBlock.text(id: 'text-a', authorId: 'A', text: 'A 的文字'),
          SharedMomentBlock.text(id: 'text-b', authorId: 'B', text: 'B 的文字'),
          SharedMomentBlock.image(
            id: 'image-a-1',
            authorId: 'A',
            imageUrl: 'https://images.invalid/a-1.jpg',
          ),
          SharedMomentBlock.image(
            id: 'image-b-1',
            authorId: 'B',
            imageUrl: 'https://images.invalid/b-1.jpg',
          ),
          SharedMomentBlock.image(
            id: 'image-a-2',
            authorId: 'A',
            imageUrl: 'https://images.invalid/a-2.jpg',
          ),
          SharedMomentBlock.image(
            id: 'image-b-2',
            authorId: 'B',
            imageUrl: 'https://images.invalid/b-2.jpg',
          ),
        ],
    createdBy: 'A',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Moment _legacyMoment() {
  final timestamp = DateTime(2025, 6, 18, 10);
  return Moment(
    id: 'legacy-a',
    dateStr: '2025-06-18',
    authorId: 'A',
    feeling: '这段旧双联内容不应显示',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

BoxDecoration _decoration(WidgetTester tester, Finder finder) =>
    tester.widget<Container>(finder).decoration! as BoxDecoration;

Border _border(BoxDecoration decoration) => decoration.border! as Border;

class _ReadingApiService extends ApiService {
  final SharedMoment moment;
  _ReadingApiService(this.moment);

  @override
  Future<SharedMoment> getSharedMomentById(String id) async => moment;
}

class _ImageConflictApiService extends ApiService {
  final SharedMoment latest;
  int calls = 0;
  List<SharedMomentBlock> lastBlocks = const [];

  _ImageConflictApiService(this.latest);

  @override
  Future<SharedMoment> updateSharedMoment({
    required SharedMoment moment,
    required List<SharedMomentBlock> blocks,
    List<Map<String, dynamic>> splitForeignText = const [],
  }) async {
    calls++;
    if (calls == 1) {
      throw SharedMomentConflictException(latest: latest);
    }
    lastBlocks = List.of(blocks);
    return latest.copyWith(revision: latest.revision + 1, blocks: lastBlocks);
  }
}

class _RecordingSaveApiService extends ApiService {
  final SharedMoment? conflictLatest;
  final bool failHandshake;
  final requests =
      <
        ({
          SharedMoment moment,
          List<SharedMomentBlock> blocks,
          List<Map<String, dynamic>> splits,
        })
      >[];

  _RecordingSaveApiService({this.conflictLatest, this.failHandshake = false});

  @override
  Future<SharedMoment> updateSharedMoment({
    required SharedMoment moment,
    required List<SharedMomentBlock> blocks,
    List<Map<String, dynamic>> splitForeignText = const [],
  }) async {
    requests.add((
      moment: moment,
      blocks: List.of(blocks),
      splits: splitForeignText
          .map(
            (split) => {
              ...split,
              if (split['fragments'] is List)
                'fragments': List.of(split['fragments'] as List),
            },
          )
          .toList(),
    ));
    if (failHandshake) throw const HandshakeException('certificate failure');
    if (requests.length == 1 && conflictLatest != null) {
      throw SharedMomentConflictException(latest: conflictLatest!);
    }
    return moment.copyWith(revision: moment.revision + 1, blocks: blocks);
  }
}

void _mockKeepAlive() {
  const foreground = MethodChannel(
    'com.splitmoments.split_moments/foreground_service',
  );
  const wakeLock = MethodChannel('com.splitmoments.split_moments/wakelock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(foreground, (_) async => null);
  messenger.setMockMethodCallHandler(wakeLock, (_) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(foreground, null);
    messenger.setMockMethodCallHandler(wakeLock, null);
  });
}

Future<SharedDocumentTextController> _showEditorText(
  WidgetTester tester,
) async {
  final editor = find.byKey(const ValueKey('shared-continuous-text-editor'));
  await tester.dragUntilVisible(
    editor,
    find.byType(ListView).last,
    const Offset(0, -300),
  );
  return tester
          .widget<TextField>(
            find.descendant(of: editor, matching: find.byType(TextField)),
          )
          .controller!
      as SharedDocumentTextController;
}

void _insertTwice(SharedDocumentTextController controller) {
  controller.selection = const TextSelection.collapsed(offset: 1);
  controller.value = const TextEditingValue(
    text: 'aXbcd',
    selection: TextSelection.collapsed(offset: 2),
  );
  controller.selection = const TextSelection.collapsed(offset: 4);
  controller.value = const TextEditingValue(
    text: 'aXbcYd',
    selection: TextSelection.collapsed(offset: 5),
  );
}

ProviderContainer _feedContainer({
  required Future<SharedMoment?> Function() loadShared,
}) {
  final pendingUsers = Completer<void>();
  final container = ProviderContainer(
    overrides: [
      loadUsersProvider.overrideWith((ref) => pendingUsers.future),
      initWallpaperProvider.overrideWith((ref) async {}),
      markedDatesProvider.overrideWith(
        (ref) async => CalendarMarkedDates.empty(),
      ),
      dayMomentsProvider.overrideWith(
        (ref) async => {'myMoment': _legacyMoment(), 'partnerMoment': null},
      ),
      sharedMomentProvider.overrideWith((ref, _) => loadShared()),
    ],
  );
  container.read(currentUserProvider.notifier).setUser(_userA);
  container.read(partnerUserProvider.notifier).setUser(_userB);
  return container;
}

Future<void> _pumpFeed(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.lightTheme, home: const FeedScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets(
    'document renders photos first and one continuous two-color text flow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SharedDiaryDocument(moment: _sharedMoment()),
            ),
          ),
        ),
      );
      await tester.pump();

      final continuous = find.byKey(const ValueKey('shared-continuous-text'));
      expect(continuous, findsOneWidget);
      final selectable = tester.widget<SelectableText>(continuous);
      final spans = selectable.textSpan!.children!.cast<TextSpan>().toList();
      expect(spans.map((span) => span.text), ['A 的文字', 'B 的文字']);
      expect(spans[0].style!.color, AppTheme.sharedUserAColor);
      expect(spans[1].style!.color, AppTheme.sharedUserBColor);

      final imageA = find.byKey(const ValueKey('shared-image-image-a-1'));
      final imageB = find.byKey(const ValueKey('shared-image-image-b-1'));
      final imageAContainer = find
          .descendant(of: imageA, matching: find.byType(Container))
          .first;
      final imageBContainer = find
          .descendant(of: imageB, matching: find.byType(Container))
          .first;
      expect(
        _border(_decoration(tester, imageAContainer)).top.color,
        AppTheme.sharedUserAColor,
      );
      expect(
        _border(_decoration(tester, imageBContainer)).top.color,
        AppTheme.sharedUserBColor,
      );
      expect(
        find.descendant(of: imageA, matching: find.text('A')),
        findsNothing,
      );
      expect(
        find.descendant(of: imageB, matching: find.text('B')),
        findsNothing,
      );

      final grid = tester.widget<GridView>(
        find.descendant(
          of: find.byKey(const ValueKey('shared-image-grid')),
          matching: find.byType(GridView),
        ),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(grid.shrinkWrap, isFalse);
      expect(grid.physics, isA<NeverScrollableScrollPhysics>());
      expect(grid.childrenDelegate.estimatedChildCount, 4);
      expect(
        tester.getTopLeft(imageA).dy,
        lessThan(tester.getTopLeft(continuous).dy),
      );
    },
  );

  testWidgets('document image area stays at two rows and scrolls after six', (
    tester,
  ) async {
    final blocks = <SharedMomentBlock>[
      for (var index = 0; index < 7; index++)
        SharedMomentBlock.image(
          id: 'image-$index',
          authorId: index.isEven ? 'A' : 'B',
          imageUrl: 'https://images.invalid/$index.jpg',
        ),
      SharedMomentBlock.text(id: 'text', authorId: 'A', text: '正文'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: SharedDiaryDocument(moment: _sharedMoment(blocks: blocks)),
          ),
        ),
      ),
    );
    await tester.pump();

    final grid = tester.widget<GridView>(
      find.descendant(
        of: find.byKey(const ValueKey('shared-image-grid')),
        matching: find.byType(GridView),
      ),
    );
    expect(grid.physics, isA<ClampingScrollPhysics>());
    expect(grid.childrenDelegate.estimatedChildCount, 7);
    expect(tester.getSize(find.byType(GridView)).height, lessThan(250));
  });

  testWidgets('editor exposes one continuous two-color editing surface', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(_userA);
    final moment = _sharedMoment(
      blocks: [
        SharedMomentBlock.text(id: 'own', authorId: 'A', text: '自己的'),
        SharedMomentBlock.text(id: 'foreign', authorId: 'B', text: '对方的'),
        SharedMomentBlock.image(
          id: 'own-image',
          authorId: 'A',
          imageUrl: 'https://images.invalid/own.jpg',
        ),
        SharedMomentBlock.image(
          id: 'foreign-image',
          authorId: 'B',
          imageUrl: 'https://images.invalid/foreign.jpg',
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharedDiaryEditorScreen(initialMoment: moment),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is LongPressDraggable<int>,
        description: 'only the signed-in author photo is draggable',
      ),
      findsOneWidget,
    );
    expect(find.text('封面'), findsNothing);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.textContaining('版本'), findsNothing);
    expect(find.text('A 的文字'), findsNothing);
    expect(find.text('B 的文字'), findsNothing);
    final photoA = find.byKey(const ValueKey('photo-slot-0'));
    final photoB = find.byKey(const ValueKey('photo-slot-1'));
    expect(
      _border(
        _decoration(
          tester,
          find.descendant(of: photoA, matching: find.byType(Container)).first,
        ),
      ).top.color,
      AppTheme.sharedUserAColor,
    );
    expect(
      _border(
        _decoration(
          tester,
          find.descendant(of: photoB, matching: find.byType(Container)).first,
        ),
      ).top.color,
      AppTheme.sharedUserBColor,
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('shared-continuous-text-editor')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    final editor = find.byKey(const ValueKey('shared-continuous-text-editor'));
    final field = tester.widget<TextField>(
      find.descendant(of: editor, matching: find.byType(TextField)),
    );
    final controller = field.controller! as SharedDocumentTextController;
    expect(controller.text, '自己的对方的');
    final span = controller.buildTextSpan(
      context: tester.element(editor),
      style: const TextStyle(),
      withComposing: false,
    );
    final runs = span.children!.cast<TextSpan>().toList();
    expect(runs, hasLength(2));
    expect(runs[0].style!.color, AppTheme.sharedUserAColor);
    expect(runs[1].style!.color, AppTheme.sharedUserBColor);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('pending split keeps its three blocks contiguous in the editor', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(_userA);
    final timestamp = DateTime(2025, 6, 18, 12);
    final source = SharedMomentBlock.text(
      id: 'foreign-source',
      authorId: 'B',
      text: '前半后半',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final moment = _sharedMoment(blocks: [source]);
    final left = source.copyWith(text: '前半');
    final inserted = SharedMomentBlock.text(
      id: 'own-insert',
      authorId: 'A',
      text: '中间',
    );
    final right = SharedMomentBlock.text(
      id: 'foreign-right',
      authorId: 'B',
      text: '后半',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharedDiaryEditorScreen(
            initialMoment: moment,
            initialBlocks: [left, inserted, right],
            initialSplitForeignText: const [
              {
                'source_block_id': 'foreign-source',
                'left_text': '前半',
                'inserted_block_id': 'own-insert',
                'right_block_id': 'foreign-right',
                'right_text': '后半',
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('shared-continuous-text-editor')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '前半中间后半');
  });

  testWidgets('image-only revision conflicts append both sides automatically', (
    tester,
  ) async {
    const foregroundChannel = MethodChannel(
      'com.splitmoments.split_moments/foreground_service',
    );
    const wakeLockChannel = MethodChannel(
      'com.splitmoments.split_moments/wakelock',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(foregroundChannel, (_) async => null);
    messenger.setMockMethodCallHandler(wakeLockChannel, (_) async => null);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(foregroundChannel, null);
      messenger.setMockMethodCallHandler(wakeLockChannel, null);
    });
    final base = _sharedMoment(
      blocks: [
        SharedMomentBlock.text(id: 'text-a', authorId: 'A', text: '正文'),
        SharedMomentBlock.image(
          id: 'base-a',
          authorId: 'A',
          imageUrl: 'https://images.invalid/base-a.jpg',
        ),
      ],
    );
    final localImage = SharedMomentBlock.image(
      id: 'local-a',
      authorId: 'A',
      imageUrl: 'https://images.invalid/local-a.jpg',
    );
    final partnerImage = SharedMomentBlock.image(
      id: 'latest-b',
      authorId: 'B',
      imageUrl: 'https://images.invalid/latest-b.jpg',
    );
    final latest = base.copyWith(
      revision: 4,
      blocks: [...base.blocks, partnerImage],
    );
    final api = _ImageConflictApiService(latest);
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(_userA);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SharedDiaryEditorScreen(
            initialMoment: base,
            initialBlocks: [...base.blocks, localImage],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存共记'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(api.calls, 2);
    expect(
      api.lastBlocks
          .where((block) => block.type == SharedMomentBlockType.image)
          .map((block) => block.id),
      ['base-a', 'local-a', 'latest-b'],
    );
    expect(find.text('处理同时修改'), findsNothing);
  });

  testWidgets(
    'revision conflict replays every insertion when source is unchanged',
    (tester) async {
      _mockKeepAlive();
      final source = SharedMomentBlock.text(
        id: 'source',
        authorId: 'B',
        text: 'abcd',
      );
      final base = _sharedMoment(blocks: [source]);
      final latest = base.copyWith(
        revision: 4,
        blocks: [
          source,
          SharedMomentBlock.text(id: 'other', authorId: 'B', text: '新内容'),
        ],
      );
      final api = _RecordingSaveApiService(conflictLatest: latest);
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).setUser(_userA);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharedDiaryEditorScreen(initialMoment: base),
          ),
        ),
      );
      await tester.pump();
      final controller = await _showEditorText(tester);
      _insertTwice(controller);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存共记'));
      await tester.pumpAndSettle();
      expect(find.text('处理同时修改'), findsOneWidget);
      await tester.ensureVisible(find.text('进入二次合并编辑'));
      await tester.tap(find.text('进入二次合并编辑'));
      await tester.pumpAndSettle();

      final merged = await _showEditorText(tester);
      expect(merged.text, 'aXbcYd新内容');
      expect(merged.splitForeignText, hasLength(1));
      final fragments = merged.splitForeignText.single['fragments'] as List;
      expect(fragments, hasLength(5));
      expect(fragments.first, 'source');
      await tester.tap(find.widgetWithText(FilledButton, '保存共记'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(api.requests, hasLength(2));
      expect(api.requests.last.moment.revision, 4);
      expect(api.requests.last.splits.single['fragments'], fragments);
      expect(api.requests.last.blocks.map((block) => block.text), [
        'a',
        'X',
        'bc',
        'Y',
        'd',
        '新内容',
      ]);
    },
  );

  testWidgets('changed source keeps all insertions only in reference draft', (
    tester,
  ) async {
    _mockKeepAlive();
    final source = SharedMomentBlock.text(
      id: 'source',
      authorId: 'B',
      text: 'abcd',
    );
    final base = _sharedMoment(blocks: [source]);
    final latest = base.copyWith(
      revision: 4,
      blocks: [source.copyWith(text: '对方更新')],
    );
    final api = _RecordingSaveApiService(conflictLatest: latest);
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(_userA);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SharedDiaryEditorScreen(initialMoment: base)),
      ),
    );
    await tester.pump();
    _insertTwice(await _showEditorText(tester));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存共记'));
    await tester.pumpAndSettle();
    expect(find.textContaining('对方修改了你准备插入的原段'), findsOneWidget);
    await tester.ensureVisible(find.text('进入二次合并编辑'));
    await tester.tap(find.text('进入二次合并编辑'));
    await tester.pumpAndSettle();

    final editor = tester.widget<SharedDiaryEditorScreen>(
      find.byType(SharedDiaryEditorScreen).last,
    );
    expect(
      editor.conflictReference!.blocks.map((block) => block.text).join(),
      'aXbcYd',
    );
    final merged = await _showEditorText(tester);
    expect(merged.text, '对方更新');
    expect(merged.splitForeignText, isEmpty);
    expect(merged.blocks.map((block) => block.id), ['source']);
  });

  testWidgets('handshake failure keeps the draft and gives a useful message', (
    tester,
  ) async {
    _mockKeepAlive();
    final source = SharedMomentBlock.text(
      id: 'source',
      authorId: 'B',
      text: 'abcd',
    );
    final base = _sharedMoment(blocks: [source]);
    final api = _RecordingSaveApiService(failHandshake: true);
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(_userA);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SharedDiaryEditorScreen(initialMoment: base)),
      ),
    );
    await tester.pump();
    final controller = await _showEditorText(tester);
    _insertTwice(controller);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存共记'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.textContaining('安全连接未建立，当前编辑内容仍在'), findsOneWidget);
    expect(controller.text, 'aXbcYd');
    expect(controller.splitForeignText.single['fragments'], hasLength(5));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存共记'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'conflict rebase never guesses lineage when a deleted block id disappears',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).setUser(_userA);
      final timestamp = DateTime(2025, 6, 18, 12);
      final original = SharedMomentBlock.text(
        id: 'own-source',
        authorId: 'A',
        text: '原文',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final base = _sharedMoment(blocks: [original]);
      final latest = base.copyWith(
        revision: 4,
        blocks: [
          SharedMomentBlock.text(
            id: 'partner-insert',
            authorId: 'B',
            text: '对方插入',
          ),
          SharedMomentBlock.text(
            id: 'own-source-right',
            authorId: 'A',
            text: '原文',
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(minutes: 1)),
          ),
        ],
      );
      final local = base.copyWith(blocks: const []);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharedDiaryConflictScreen(
              base: base,
              latest: latest,
              localDraft: local,
              currentUserId: 'A',
              splitForeignText: const [],
            ),
          ),
        ),
      );
      expect(find.textContaining('已被拆分或删除'), findsWidgets);
      await tester.tap(find.text('进入二次合并编辑'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const ValueKey('shared-continuous-text-editor')),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '对方插入原文');
    },
  );

  testWidgets('shared day view remains usable on a narrow short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SharedDayView(
                moment: _sharedMoment(blocks: const []),
                cardOpacity: 1,
                onOpenReading: () {},
                onEdit: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('展开共记'), findsOneWidget);
    expect(find.text('开始共写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Feed gives an existing shared diary priority over legacy cards',
    (tester) async {
      final container = _feedContainer(loadShared: () async => _sharedMoment());
      addTearDown(container.dispose);
      await _pumpFeed(tester, container);

      expect(find.byKey(const ValueKey('shared-diary-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-split-page')), findsNothing);
      final card = find.byKey(const ValueKey('shared-diary-page'));
      expect(
        find.descendant(of: card, matching: find.byType(AvatarWidget)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Alice')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Bob')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('v3')),
        findsNothing,
      );
      expect(find.descendant(of: card, matching: find.text('A')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('B')), findsNothing);
      expect(
        find.byKey(const ValueKey('shared-continuous-text')),
        findsOneWidget,
      );
      expect(find.text('这段旧双联内容不应显示'), findsNothing);
      expect(find.text('查看保留的旧双联'), findsOneWidget);
    },
  );

  testWidgets(
    'reading and conflict pages omit identities and version numbers',
    (tester) async {
      final moment = _sharedMoment();
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(_ReadingApiService(moment)),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).setUser(_userA);
      container.read(partnerUserProvider.notifier).setUser(_userB);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SharedDiaryReadingScreen(initialMoment: moment),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(AvatarWidget), findsNothing);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      expect(find.textContaining('版本 3'), findsNothing);
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: SharedDiaryConflictScreen(
            base: moment,
            latest: moment,
            localDraft: moment,
            currentUserId: 'A',
            splitForeignText: const [],
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('v3'), findsNothing);
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    },
  );

  testWidgets('ordinary photo picker still marks its first photo as cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoGridPicker(
            entries: const [PhotoEntry.url('https://images.invalid/cover.jpg')],
            onAdded: (_) {},
            onRemoved: (_) {},
            onReordered: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('封面'), findsOneWidget);
  });

  testWidgets('Feed does not treat an unknown shared state as legacy mode', (
    tester,
  ) async {
    final container = _feedContainer(
      loadShared: () async => throw Exception('offline'),
    );
    addTearDown(container.dispose);
    await _pumpFeed(tester, container);
    await tester.pumpAndSettle();

    expect(find.textContaining('暂时无法确认当天是否为共记模式'), findsOneWidget);
    expect(find.byKey(const ValueKey('diary-split-page')), findsNothing);
    expect(find.widgetWithText(TextButton, '共记模式'), findsNothing);
  });
}
