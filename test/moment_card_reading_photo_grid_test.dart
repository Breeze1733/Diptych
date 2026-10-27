import 'package:diptych/models/moment.dart';
import 'package:diptych/widgets/image_gallery.dart';
import 'package:diptych/widgets/moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void _expectStaticThreeColumnGrid(int count) {
  final grid = find.byKey(const ValueKey('diary-reading-photo-grid'));
  expect(grid, findsOneWidget);
  final widget = testerWidget<GridView>(grid);
  expect(widget.childrenDelegate.estimatedChildCount, count);
  expect(widget.shrinkWrap, isTrue);
  expect(widget.primary, isFalse);
  expect(widget.physics, isA<NeverScrollableScrollPhysics>());
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
  testWidgets(
    'one photo is a square tile in a non-scrolling three-column grid',
    (tester) async {
      await _pumpReadingCard(tester, 1);

      _expectStaticThreeColumnGrid(1);
      expect(_photo(0), findsOneWidget);
      final size = tester.getSize(_photo(0));
      expect(size.width, closeTo(size.height, .01));
      expect(find.text('添加图片'), findsNothing);
    },
  );

  testWidgets('six photos occupy two complete rows', (tester) async {
    await _pumpReadingCard(tester, 6);

    _expectStaticThreeColumnGrid(6);
    expect(find.byKey(const ValueKey('diary-reading-photo-5')), findsOneWidget);
    final firstRow = tester.getTopLeft(_photo(0));
    final firstRowEnd = tester.getTopLeft(_photo(2));
    final secondRow = tester.getTopLeft(_photo(3));
    final secondRowEnd = tester.getTopLeft(_photo(5));
    expect(firstRow.dy, closeTo(firstRowEnd.dy, .01));
    expect(secondRow.dy, closeTo(secondRowEnd.dy, .01));
    expect(secondRow.dy, greaterThan(firstRow.dy));
  });

  testWidgets('seventh photo expands a third row and opens at its own index', (
    tester,
  ) async {
    await _pumpReadingCard(tester, 7);

    _expectStaticThreeColumnGrid(7);
    final secondRow = tester.getTopLeft(_photo(3));
    final thirdRow = tester.getTopLeft(_photo(6));
    expect(thirdRow.dy, greaterThan(secondRow.dy));

    await tester.tap(_photo(6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final viewer = tester.widget<FullScreenImage>(find.byType(FullScreenImage));
    expect(viewer.initialIndex, 6);
    expect(viewer.urls, _momentWithPhotos(7).imageUrls);
  });
}
