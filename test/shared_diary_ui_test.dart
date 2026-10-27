import 'dart:async';

import 'package:diptych/constants/app_theme.dart';
import 'package:diptych/models/app_user.dart';
import 'package:diptych/models/calendar_marked_dates.dart';
import 'package:diptych/models/moment.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/providers/day_moment_provider.dart';
import 'package:diptych/providers/wallpaper_provider.dart';
import 'package:diptych/screens/feed_screen.dart';
import 'package:diptych/screens/shared_diary_editor_screen.dart';
import 'package:diptych/widgets/shared_day_view.dart';
import 'package:diptych/widgets/shared_diary_document.dart';
import 'package:flutter/material.dart';
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
    'document keeps A blue and B pink with a static three-column grid',
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

      final textADecoration = _decoration(
        tester,
        find.byKey(const ValueKey('shared-text-text-a')),
      );
      final textBDecoration = _decoration(
        tester,
        find.byKey(const ValueKey('shared-text-text-b')),
      );
      expect(_border(textADecoration).left.color, AppTheme.sharedUserAColor);
      expect(_border(textBDecoration).left.color, AppTheme.sharedUserBColor);

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
          of: find.byKey(const ValueKey('shared-image-grid-0')),
          matching: find.byType(GridView),
        ),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(grid.shrinkWrap, isTrue);
      expect(grid.physics, isA<NeverScrollableScrollPhysics>());
      expect(grid.childrenDelegate.estimatedChildCount, 4);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('shared-image-image-b-2')))
            .dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('shared-image-image-a-1')))
              .dy,
        ),
      );
    },
  );

  testWidgets(
    'editor exposes editing and deletion only for the signed-in author',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).setUser(_userA);
      final moment = _sharedMoment(
        blocks: [
          SharedMomentBlock.text(id: 'own', authorId: 'A', text: '自己的'),
          SharedMomentBlock.text(id: 'foreign', authorId: 'B', text: '对方的'),
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

      final own = find.byKey(const ValueKey('shared-editor-text-own'));
      final foreign = find.byKey(const ValueKey('shared-editor-text-foreign'));
      expect(
        find.descendant(of: own, matching: find.byType(TextField)),
        findsOne,
      );
      expect(
        find.descendant(of: foreign, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: own, matching: find.byTooltip('删除这段')),
        findsOne,
      );
      expect(
        find.descendant(of: foreign, matching: find.byTooltip('删除这段')),
        findsNothing,
      );
      expect(find.text('在这段中插入'), findsOneWidget);
    },
  );

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

    expect(find.text('在这里接着写'), findsOneWidget);
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

      expect(
        find.byKey(const ValueKey('shared-editor-text-partner-insert')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shared-editor-text-own-source-right')),
        findsOneWidget,
      );
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
      expect(find.text('A 的文字'), findsOneWidget);
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
