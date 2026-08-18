import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/moment.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
import '../utils/wakelock_helper.dart';
import 'auth_provider.dart';
import 'selected_date_provider.dart';

/// 预加载当天日记的所有图片（双方所有图片）并在此期间申请 10 分钟 CPU WakeLock 保活
void preloadDayImages(List<Moment> moments) {
  final urls = <String>{};
  for (final m in moments) {
    for (final url in m.imageUrls) {
      if (url.isNotEmpty) urls.add(url);
    }
  }

  if (urls.isEmpty) return;

  // 异步下载，附带 CPU 唤醒锁保活（最长 10 分钟）
  Future(() async {
    await WakelockHelper.acquire(timeout: const Duration(minutes: 10));
    try {
      final cacheManager = DefaultCacheManager();
      await Future.wait(
        urls.map((url) async {
          try {
            await cacheManager.getSingleFile(url);
          } catch (_) {}
        }),
      );
    } catch (_) {
    } finally {
      await WakelockHelper.release();
    }
  });
}

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

/// 选定日期的双方动态（缓存优先，立即返回；invalidate 后重读缓存）
final FutureProvider<Map<String, Moment?>> dayMomentsProvider = FutureProvider<Map<String, Moment?>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final dateStr = DateHelper.toDateStr(selectedDate);
  final currentUser = ref.watch(currentUserProvider);
  final partner = ref.watch(partnerUserProvider);

  if (currentUser == null || partner == null) {
    return {'myMoment': null, 'partnerMoment': null};
  }

  // 加载缓存（null = 从未请求过该日期，[] = 请求过但无数据）
  final cached = await CacheService.loadDayMoments(dateStr);

  if (cached != null) {
    // 缓存命中（包括空数据）→ 秒返，后台静默刷新
    // 后台拉取最新（不阻塞，有变化才刷新 UI）
    final apiService = ref.read(apiServiceProvider);
    final oldJson = jsonEncode(cached);
    final selfRef = ref;
    apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]).then((moments) async {
      final newRaw = moments.map((m) => m.toJson()).toList();
      if (jsonEncode(newRaw) != oldJson) {
        await CacheService.saveDayMoments(dateStr, newRaw);
        preloadDayImages(moments);
        selfRef.invalidate(dayMomentsProvider);
      }
    }).catchError((_) {});

    if (cached.isEmpty) return {'myMoment': null, 'partnerMoment': null};
    final moments = cached.map((e) => Moment.fromJson(e)).toList();
    preloadDayImages(moments);
    return _splitMoments(
      moments,
      currentUser.uid,
      partner.uid,
    );
  }

  // 从未请求过 → 等网络（仅首次）
  final apiService = ref.read(apiServiceProvider);
  try {
    final moments = await apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]);
    // 即使空也保存，下次秒开
    await CacheService.saveDayMoments(dateStr, moments.map((m) => m.toJson()).toList());
    preloadDayImages(moments);
    return _splitMoments(moments, currentUser.uid, partner.uid);
  } catch (_) {
    return {'myMoment': null, 'partnerMoment': null};
  }
});

/// 日历圆点（只增不减，纯缓存；仅首次无缓存时调一次 API）
final FutureProvider<List<DateTime>> markedDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  final cached = await CacheService.loadMarkedDates(currentUser.uid);

  if (cached != null) {
    // 缓存命中（包括空数据）→ 秒返
    return cached.map((s) => DateHelper.parseDateStr(s)).toList();
  }

  // 首次使用 → 从后端拉一次
  try {
    final apiService = ref.read(apiServiceProvider);
    final dateStrs = await apiService.getDatesWithMoments(currentUser.uid);
    await CacheService.saveMarkedDates(currentUser.uid, dateStrs);
    return dateStrs.map((s) => DateHelper.parseDateStr(s)).toList();
  } catch (_) {
    return [];
  }
});

/// 保存后更新日历圆点：本地缓存追加当天日期（不调 API）
Future<void> updateMarkedDateCache(WidgetRef ref) async {
  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) return;

  final dateStr = DateHelper.toDateStr(ref.read(selectedDateProvider));
  final cached = await CacheService.loadMarkedDates(currentUser.uid) ?? [];
  if (!cached.contains(dateStr)) {
    cached.add(dateStr);
    cached.sort();
    await CacheService.saveMarkedDates(currentUser.uid, cached);
  }
  ref.invalidate(markedDatesProvider);
}
