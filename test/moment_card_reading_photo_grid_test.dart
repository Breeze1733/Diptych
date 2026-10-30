import 'package:diptych/models/app_user.dart';
import 'package:diptych/models/moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/screens/diary_reading_screen.dart';
import 'package:diptych/screens/edit_moment_screen.dart';
import 'package:diptych/services/api_service.dart';
import 'package:diptych/widgets/image_gallery.dart';
import 'package:diptych/widgets/moment_card.dart';
import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadingApi extends ApiService {
  final Moment moment;
  _ReadingApi(this.moment);
  @override
  Future<Moment> getMoment(String id) async => moment;
}

Moment _momentWithPhotos(int count) {
  final createdAt = DateTime(2025, 1, 2, 8);
  return Moment(
    id: 'moment-$count',
    dateStr: '2025-01-02',
    authorId: 'A',
    imageUrls: List.generate(
      count,
      (index) => 'https://images.invalid/photo-$index.jpg',
    ),
    feeling: '正文',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

Future<void> _pumpReadingCard(WidgetTester tester, int count) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 390,
            child: MomentCard(
              moment: _momentWithPhotos(count),
              nickname: '用户A',
              expandedReading: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _photo(int index) => find.byKey(ValueKey('diary-reading-photo-$index'));

void _expectThreeColumnGrid(int count, {bool scrollable = false}) {
  final grid = find.byKey(const ValueKey('diary-reading-photo-grid'));
  expect(grid, findsOneWidget);
  final widget = testerWidget<GridView>(grid);
  expect(widget.childrenDelegate.estimatedChildCount, count);
  expect(widget.shrinkWrap, isFalse);
  expect(widget.primary, isFalse);
  if (scrollable) {
    expect(widget.physics, isA<ClampingScrollPhysics>());
  } else {
    expect(widget.physics, isA<NeverScrollableScrollPhysics>());
  }
  final delegate =
      widget.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  expect(delegate.crossAxisCount, 3);
  expect(delegate.mainAxisSpacing, 8);
  expect(delegate.crossAxisSpacing, 8);
}

T testerWidget<T extends Widget>(Finder finder) {
  final element = finder.evaluate().single;
  return element.widget as T;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'one photo is a square tile in a non-scrolling three-column grid',
    (tester) async {
      await _pumpReadingCard(tester, 1);

      _expectThreeColumnGrid(1);
      expect(_photo(0), findsOneWidget);
      final size = tester.getSize(_photo(0));
      expect(size.width, closeTo(size.height, .01));
      expect(find.text('添加图片'), findsNothing);
    },
  );

  testWidgets('six photos occupy two complete rows', (tester) async {
    await _pumpReadingCard(tester, 6);

    _expectThreeColumnGrid(6);
    expect(find.byKey(const ValueKey('diary-reading-photo-5')), findsOneWidget);
    final firstRow = tester.getTopLeft(_photo(0));
    final firstRowEnd = tester.getTopLeft(_photo(2));
    final secondRow = tester.getTopLeft(_photo(3));
    final secondRowEnd = tester.getTopLeft(_photo(5));
    expect(firstRow.dy, closeTo(firstRowEnd.dy, .01));
    expect(secondRow.dy, closeTo(secondRowEnd.dy, .01));
    expect(secondRow.dy, greaterThan(firstRow.dy));
  });

  testWidgets(
    'seventh photo scrolls inside two rows and opens at its own index',
    (tester) async {
      await _pumpReadingCard(tester, 7);

      _expectThreeColumnGrid(7, scrollable: true);
      final grid = find.byKey(const ValueKey('diary-reading-photo-grid'));
      final tile = tester.getSize(_photo(0));
      expect(tester.getSize(grid).height, closeTo(tile.height * 2 + 8, .01));
      await tester.drag(grid, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.widget<GridView>(grid).controller!.offset, greaterThan(0));

      await tester.tap(_photo(6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final viewer = tester.widget<FullScreenImage>(
        find.byType(FullScreenImage),
      );
      expect(viewer.initialIndex, 6);
      expect(viewer.urls, _momentWithPhotos(7).imageUrls);
    },
  );

  Future<void> pumpDiary(
    WidgetTester tester, {
    bool editing = false,
    int count = 12,
  }) async {
    final moment = _momentWithPhotos(count);
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(_ReadingApi(moment))],
    );
    addTearDown(container.dispose);
    container
        .read(currentUserProvider.notifier)
        .setUser(const AppUser(uid: 'A', nickname: '用户A', partnerUid: 'B'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: editing
              ? EditMomentScreen(
                  date: DateTime(2025, 1, 2),
                  existingMoment: moment,
                )
              : DiaryReadingScreen(initialMoment: moment),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordinary details expand from a compact action beside refresh and collapse to local scrolling',
    (tester) async {
      await pumpDiary(tester);
      final grid = find.byKey(const ValueKey('diary-reading-photo-grid'));
      final collapsed = tester.getSize(grid).height;
      final expand = find.byTooltip('展开图片列表');
      final refresh = find.byTooltip('刷新这条日记');
      expect(
        find.descendant(of: find.byType(AppBar), matching: expand),
        findsOneWidget,
      );
      expect(tester.getSize(expand).width, lessThanOrEqualTo(48));
      expect(
        tester.getCenter(expand).dy,
        closeTo(tester.getCenter(refresh).dy, .01),
      );
      expect(
        tester.getCenter(expand).dx,
        lessThan(tester.getCenter(refresh).dx),
      );
      expect(find.widgetWithText(TextButton, '展开图片列表'), findsNothing);
      _expectThreeColumnGrid(12, scrollable: true);
      await tester.drag(grid, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.widget<GridView>(grid).controller!.offset, greaterThan(0));
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(tester.getSize(grid).height, greaterThan(collapsed * 1.8));
      _expectThreeColumnGrid(12);
      await tester.tap(find.byTooltip('收起图片列表'));
      await tester.pumpAndSettle();
      expect(tester.getSize(grid).height, collapsed);
      _expectThreeColumnGrid(12, scrollable: true);
    },
  );

  testWidgets(
    'ordinary editor keeps two rows without expansion or refresh actions',
    (tester) async {
      await pumpDiary(tester, editing: true);
      final picker = tester.widget<PhotoGridPicker>(
        find.byType(PhotoGridPicker),
      );
      expect(picker.visibleRows, 2);
      expect(find.byTooltip('展开图片列表'), findsNothing);
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
}
