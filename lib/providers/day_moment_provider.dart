import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/moment.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
import 'auth_provider.dart';
import 'selected_date_provider.dart';

/// 手动刷新触发器：每次递增触发重新拉取后端
final refreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 后端是否在线（能否连上）
final backendOnlineProvider = StateProvider<bool>((ref) => true);

/// 选定日期的双方动态（缓存优先，后端兜底）
final dayMomentsProvider = FutureProvider<Map<String, Moment?>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final dateStr = DateHelper.toDateStr(selectedDate);
  final currentUser = ref.watch(currentUserProvider);
  final partner = ref.watch(partnerUserProvider);

  // 监听刷新触发器
  ref.watch(refreshTriggerProvider);

  if (currentUser == null || partner == null) {
    return {'myMoment': null, 'partnerMoment': null};
  }

  // 先尝试从缓存加载
  final cached = await CacheService.loadDayMoments(dateStr);
  bool cacheReturned = false;

  if (cached != null && cached.isNotEmpty) {
    // 有缓存数据，后续异步刷新
    cacheReturned = true;
  }

  try {
    final apiService = ref.read(apiServiceProvider);
    final moments = await apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]);

    // 更新缓存
    final raw = moments.map((m) => m.toJson()).toList();
    await CacheService.saveDayMoments(dateStr, raw);

    // 标记后端在线
    ref.read(backendOnlineProvider.notifier).state = true;

    Moment? myMoment;
    Moment? partnerMoment;
    for (final m in moments) {
      if (m.authorId == currentUser.uid) {
        myMoment = m;
      } else if (m.authorId == partner.uid) {
        partnerMoment = m;
      }
    }
    return {'myMoment': myMoment, 'partnerMoment': partnerMoment};
  } catch (_) {
    // 后端不通 → 标记离线，回退缓存
    ref.read(backendOnlineProvider.notifier).state = false;

    if (cacheReturned) {
      final moments = cached!.map((e) => Moment.fromJson(e)).toList();
      Moment? myMoment;
      Moment? partnerMoment;
      for (final m in moments) {
        if (m.authorId == currentUser.uid) {
          myMoment = m;
        } else if (m.authorId == partner.uid) {
          partnerMoment = m;
        }
      }
      return {'myMoment': myMoment, 'partnerMoment': partnerMoment};
    }

    return {'myMoment': null, 'partnerMoment': null};
  }
});

/// 标记日期提供者（缓存优先）
final markedDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  ref.watch(refreshTriggerProvider);

  try {
    final apiService = ref.read(apiServiceProvider);
    final dateStrs = await apiService.getDatesWithMoments(currentUser.uid);
    await CacheService.saveMarkedDates(currentUser.uid, dateStrs);
    ref.read(backendOnlineProvider.notifier).state = true;
    return dateStrs.map((s) => DateHelper.parseDateStr(s)).toList();
  } catch (_) {
    ref.read(backendOnlineProvider.notifier).state = false;
    final cached = await CacheService.loadMarkedDates(currentUser.uid);
    if (cached != null) {
      return cached.map((s) => DateHelper.parseDateStr(s)).toList();
    }
    return [];
  }
});

/// 刷新所有数据（发布/修改/评论后调用）
void refreshAllData(WidgetRef ref) {
  ref.read(refreshTriggerProvider.notifier).state++;
}
