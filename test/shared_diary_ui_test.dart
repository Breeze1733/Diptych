import 'dart:async';

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
import 'package:diptych/services/api_service.dart';
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
                userAName: '名字很长的用户 Alice',
                userBName: '名字同样很长的用户 Bob',
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
      expect(
        find.byKey(const ValueKey('shared-continuous-text')),
        findsOneWidget,
      );
      expect(find.text('这段旧双联内容不应显示'), findsNothing);
      expect(find.text('查看保留的旧双联'), findsOneWidget);
    },
  );

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
