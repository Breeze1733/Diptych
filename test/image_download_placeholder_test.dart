import 'package:diptych/services/image_download_progress.dart';
import 'package:diptych/widgets/image_download_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows queue, connection and actual byte percentages', (
    tester,
  ) async {
    final tracker = ImageDownloadTracker();
    addTearDown(tracker.dispose);
    const url = 'https://images.test/photo.jpg';
    await tester.pumpWidget(_placeholder(tracker, url));
    expect(find.text('排队中'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    tracker.start(url);
    await tester.pumpAndSettle();
    expect(find.text('连接中'), findsOneWidget);
    tracker.preparing(url);
    await tester.pumpAndSettle();
    expect(find.text('正在生成预览'), findsOneWidget);
    tracker.update(url, 25, 100);
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
    tracker.update(url, 100, 100);
    await tester.pumpAndSettle();
    expect(find.text('99%'), findsOneWidget);
    tracker.complete(url);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('shows downloaded bytes when content length is unknown', (
    tester,
  ) async {
    final tracker = ImageDownloadTracker();
    addTearDown(tracker.dispose);
    const url = 'https://images.test/chunked.jpg';
    tracker.update(url, 1024, null);
    await tester.pumpWidget(_placeholder(tracker, url));
    expect(find.text('已下载 1 KB'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('switches URLs without displaying another image progress', (
    tester,
  ) async {
    final tracker = ImageDownloadTracker();
    addTearDown(tracker.dispose);
    const first = 'https://images.test/first.jpg';
    const second = 'https://images.test/second.jpg';
    tracker.update(first, 75, 100);
    await tester.pumpWidget(_placeholder(tracker, first));
    expect(find.text('75%'), findsOneWidget);
    await tester.pumpWidget(_placeholder(tracker, second));
    expect(find.text('排队中'), findsOneWidget);
    tracker.update(first, 90, 100);
    await tester.pumpAndSettle();
    expect(find.text('排队中'), findsOneWidget);
    tracker.update(second, 50, 100);
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('fits queue and progress text into small avatars', (
    tester,
  ) async {
    final tracker = ImageDownloadTracker();
    addTearDown(tracker.dispose);
    const url = 'https://images.test/avatar.jpg';
    await tester.pumpWidget(_placeholder(tracker, url, size: 24));
    expect(find.text('排队中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tracker.update(url, 1, 2);
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _placeholder(
  ImageDownloadTracker tracker,
  String url, {
  double size = 120,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: size,
        child: ImageDownloadPlaceholder(url: url, tracker: tracker),
      ),
    ),
  ),
);
