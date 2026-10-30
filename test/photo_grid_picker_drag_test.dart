import 'package:diptych/widgets/photo_grid_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
      'recycled drag source still tracks movement and stops on ${cancel ? 'cancel' : 'drop'}',
      (tester) async {
        int? movedTo;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 215,
                child: PhotoGridPicker(
                  entries: [
                    for (var i = 0; i < 120; i++)
                      PhotoEntry.url('https://images.invalid/$i.jpg'),
                  ],
                  visibleRows: 2,
                  onAdded: (_) {},
                  onRemoved: (_) {},
                  onReordered: (_, index) => movedTo = index,
                ),
              ),
            ),
          ),
        );
        final grid = find.byKey(const ValueKey('diary-photo-grid'));
        final box = tester.getRect(grid);
        final controller = tester.widget<GridView>(grid).controller!;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('photo-slot-0'))),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(Offset(box.center.dx, box.bottom - 4));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('photo-slot-0')), findsNothing);

        // The grid must keep tracking the pointer after its source is recycled.
        await gesture.moveTo(box.center);
        await tester.pump();
        final middleOffset = controller.offset;
        await tester.pump(const Duration(milliseconds: 240));
        expect(controller.offset, middleOffset);

        await gesture.moveTo(Offset(box.center.dx, box.bottom - 4));
        await tester.pump(const Duration(milliseconds: 120));
        expect(controller.offset, greaterThan(middleOffset));
        // Refresh hit testing against the newly revealed drop target.
        await gesture.moveBy(const Offset(1, -1));
        await tester.pump();
        if (cancel) {
          // Release outside every target to exercise an unaccepted drag.
          await gesture.moveTo(Offset(box.right + 50, box.bottom - 4));
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump();
        final releasedOffset = controller.offset;
        await tester.pump(const Duration(milliseconds: 240));
        final stoppedOffset = controller.offset;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(stoppedOffset, releasedOffset);
        expect(movedTo, cancel ? isNull : greaterThan(5));
      },
    );
  }
}
