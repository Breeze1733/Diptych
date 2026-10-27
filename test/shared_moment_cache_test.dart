import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/services/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uncached and cached-null shared days remain distinguishable', () async {
    final missing = await CacheService.loadSharedMoment('2025-06-18');
    expect(missing.isCached, isFalse);
    expect(missing.moment, isNull);

    await CacheService.saveSharedMoment('2025-06-18', null);
    final empty = await CacheService.loadSharedMoment('2025-06-18');
    expect(empty.isCached, isTrue);
    expect(empty.moment, isNull);
  });

  test('shared moment and shared dates survive a cache round trip', () async {
    final moment = SharedMoment(
      id: 'shared-1',
      dateStr: '2025-06-18',
      revision: 2,
      blocks: [SharedMomentBlock.text(id: 'b-1', authorId: 'A', text: '你好')],
      createdAt: DateTime.parse('2025-06-18T08:00:00+08:00'),
      updatedAt: DateTime.parse('2025-06-18T09:00:00+08:00'),
    );

    await CacheService.saveSharedMoment(moment.dateStr, moment);
    await CacheService.saveSharedMomentDates(['2025-06-18', '2025-06-19']);

    final cached = await CacheService.loadSharedMoment(moment.dateStr);
    expect(cached.isCached, isTrue);
    expect(cached.moment?.revision, 2);
    expect(cached.moment?.blocks.single.id, 'b-1');
    expect(await CacheService.loadSharedMomentDates(), [
      '2025-06-18',
      '2025-06-19',
    ]);
  });

  test('saving one day updates an existing full shared-dates cache', () async {
    await CacheService.saveSharedMomentDates(['2025-06-19']);
    final moment = SharedMoment(
      id: 'shared-1',
      dateStr: '2025-06-18',
      revision: 0,
      createdAt: DateTime.parse('2025-06-18T08:00:00+08:00'),
      updatedAt: DateTime.parse('2025-06-18T08:00:00+08:00'),
    );

    await CacheService.saveSharedMoment(moment.dateStr, moment);
    expect(await CacheService.loadSharedMomentDates(), [
      '2025-06-18',
      '2025-06-19',
    ]);

    await CacheService.saveSharedMoment(moment.dateStr, null);
    expect(await CacheService.loadSharedMomentDates(), ['2025-06-19']);
  });
}
