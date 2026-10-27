import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/providers/auth_provider.dart';
import 'package:diptych/providers/day_moment_provider.dart';
import 'package:diptych/services/api_service.dart';
import 'package:diptych/services/cache_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiService extends ApiService {
  _FakeApiService({
    this.sharedMoment,
    this.sharedDatesError,
  });

  SharedMoment? sharedMoment;
  Object? sharedDatesError;
  int sharedMomentCalls = 0;

  @override
  Future<SharedMoment?> getSharedMoment(String dateStr) async {
    sharedMomentCalls++;
    return sharedMoment;
  }

  @override
  Future<Map<String, List<String>>> getCalendarDates() async {
    return {
      'A': ['2025-06-18'],
      'B': <String>[],
    };
  }

  @override
  Future<List<String>> getSharedMomentDates() async {
    if (sharedDatesError case final error?) throw error;
    return ['2025-06-19'];
  }
}

SharedMoment _moment() {
  final timestamp = DateTime(2025, 6, 18, 12);
  return SharedMoment(
    id: 'shared-provider',
    dateStr: '2025-06-18',
    revision: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('cached null is revalidated before legacy mode is exposed', () async {
    await CacheService.saveSharedMoment('2025-06-18', null);
    final service = _FakeApiService(sharedMoment: _moment());
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      sharedMomentProvider('2025-06-18'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final result = await container.read(
      sharedMomentProvider('2025-06-18').future,
    );

    expect(service.sharedMomentCalls, 1);
    expect(result?.id, 'shared-provider');
  });

  test(
    'calendar keeps a successful legacy refresh when shared dates fail',
    () async {
      await CacheService.saveSharedMomentDates(['2025-06-17']);
      final service = _FakeApiService(
        sharedDatesError: StateError('shared dates offline'),
      );
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final result = await container.read(markedDatesProvider.future);

      expect(result.userADates, {'2025-06-17', '2025-06-18'});
      expect(result.userBDates, {'2025-06-17'});
      expect(await CacheService.loadMarkedDates('A'), ['2025-06-18']);
      expect(await CacheService.loadSharedMomentDates(), ['2025-06-17']);
    },
  );
}
