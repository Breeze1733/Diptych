import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/moment.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
import 'auth_provider.dart';
import 'selected_date_provider.dart';

/// 当天日记刷新触发器：每次递增触发重新拉取后端
final dayRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 标记日期刷新触发器：仅在需要更新日历圆点时递增
final markedRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 后端是否在线（能否连上）
final backendOnlineProvider = StateProvider<bool>((ref) => true);

/// 解析动态列表，分出自己和对方的
Map<String, Moment?> _splitMoments(List<Moment> moments, String myUid, String partnerUid) {
  Moment? myMoment;
  Moment? partnerMoment;
  for (final m in moments) {
    if (m.authorId == myUid) {
      myMoment = m;
    } else if (m.authorId == partnerUid) {
      partnerMoment = m;
    }
  }
  return {'myMoment': myMoment, 'partnerMoment': partnerMoment};
}

/// 选定日期的双方动态（缓存优先，立即返回；后台拉取到新数据后自动刷新 UI）
final FutureProvider<Map<String, Moment?>> dayMomentsProvider = FutureProvider<Map<String, Moment?>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final dateStr = DateHelper.toDateStr(selectedDate);
  final currentUser = ref.watch(currentUserProvider);
  final partner = ref.watch(partnerUserProvider);

  // 监听刷新触发器（手动刷新时会递增）
  ref.watch(dayRefreshTriggerProvider);

  if (currentUser == null || partner == null) {
    return {'myMoment': null, 'partnerMoment': null};
  }

  final apiService = ref.read(apiServiceProvider);

  // 1. 加载缓存
  final cached = await CacheService.loadDayMoments(dateStr);

  if (cached != null && cached.isNotEmpty) {
    // 缓存命中 → 立即返回，后台静默拉取
    ref.read(backendOnlineProvider.notifier).state = true;

    // 后台刷新：对比新旧数据，有变化才刷新 UI
    final cachedJson = jsonEncode(cached);
    final selfRef = ref;
    apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]).then((moments) async {
      final newRaw = moments.map((m) => m.toJson()).toList();
      final newJson = jsonEncode(newRaw);
      if (newJson != cachedJson) {
        await CacheService.saveDayMoments(dateStr, newRaw);
        selfRef.invalidate(dayMomentsProvider);
      }
    }).catchError((_) {});

    return _splitMoments(
      cached.map((e) => Moment.fromJson(e)).toList(),
      currentUser.uid,
      partner.uid,
    );
  }

  // 2. 无缓存 → 必须等网络
  try {
    final moments = await apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]);
    await CacheService.saveDayMoments(dateStr, moments.map((m) => m.toJson()).toList());
    ref.read(backendOnlineProvider.notifier).state = true;
    return _splitMoments(moments, currentUser.uid, partner.uid);
  } catch (_) {
    ref.read(backendOnlineProvider.notifier).state = false;
    return {'myMoment': null, 'partnerMoment': null};
  }
});

/// 标记日期提供者（缓存优先，立即返回；后台拉取到新数据后自动刷新 UI）
final FutureProvider<List<DateTime>> markedDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  // 监听标记日期刷新触发器
  ref.watch(markedRefreshTriggerProvider);

  final apiService = ref.read(apiServiceProvider);

  // 1. 加载缓存
  final cached = await CacheService.loadMarkedDates(currentUser.uid);

  if (cached != null && cached.isNotEmpty) {
    // 缓存命中 → 立即返回（日历圆点不需要后台刷新，仅在新建日记时手动刷新）
    ref.read(backendOnlineProvider.notifier).state = true;
    return cached.map((s) => DateHelper.parseDateStr(s)).toList();
  }

  // 2. 无缓存 → 必须等网络
  try {
    final dateStrs = await apiService.getDatesWithMoments(currentUser.uid);
    await CacheService.saveMarkedDates(currentUser.uid, dateStrs);
    ref.read(backendOnlineProvider.notifier).state = true;
    return dateStrs.map((s) => DateHelper.parseDateStr(s)).toList();
  } catch (_) {
    ref.read(backendOnlineProvider.notifier).state = false;
    return [];
  }
});

/// 刷新当天日记（发布/修改/评论后调用）
void refreshDayData(WidgetRef ref) {
  ref.read(dayRefreshTriggerProvider.notifier).state++;
}

/// 刷新标记日期（新建日记后调用，更新日历圆点）
void refreshMarkedDates(WidgetRef ref) {
  ref.read(markedRefreshTriggerProvider.notifier).state++;
}
