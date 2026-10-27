import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/moment.dart';
import '../models/calendar_marked_dates.dart';
import '../models/shared_moment.dart';
import '../services/cache_service.dart';
import '../services/private_image_cache.dart';
import '../utils/date_helper.dart';
import '../services/transfer_keep_alive.dart';
import 'auth_provider.dart';
import 'selected_date_provider.dart';

/// 后台图片预加载队列管理：
/// 异步并行下载未缓存图片，同时持有 CPU WakeLock 和前台通知保活服务，确保切后台时网络不中断
final Set<String> _pendingPreloadUrls = {};
final Set<String> _inFlightPreloadUrls = {};
bool _isPreloadWorkerRunning = false;
int _preloadTotalCount = 0;
int _preloadDoneCount = 0;

Future<({T? value, Object? error})> _capture<T>(Future<T> future) async {
  try {
    return (value: await future, error: null);
  } catch (error) {
    return (value: null, error: error);
  }
}

/// 异步并行预加载当天日记的所有图片（双方所有图片），切后台不断流
void preloadDayImages(List<Moment> moments) {
  final targetUrls = <String>{};
  for (final m in moments) {
    for (final url in m.imageUrls) {
      if (url.isNotEmpty) targetUrls.add(url);
    }
  }

  _preloadImageUrls(targetUrls);
}

void preloadSharedMomentImages(SharedMoment moment) {
  _preloadImageUrls(
    moment.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl),
  );
}

void _preloadImageUrls(Iterable<String> urls) {
  final targetUrls = urls.where((url) => url.isNotEmpty).toSet();
  if (targetUrls.isEmpty) return;

  // 异步处理，绝不阻塞 UI 渲染
  Future(() async {
    final cacheManager = PrivateImageCache();
    final newUrls = <String>[];

    for (final url in targetUrls) {
      if (_inFlightPreloadUrls.contains(url) ||
          _pendingPreloadUrls.contains(url)) {
        continue;
      }
      final fileInfo = await cacheManager.getFileFromCache(url);
      if (fileInfo == null) {
        newUrls.add(url);
      }
    }

    if (newUrls.isEmpty) return;

    _pendingPreloadUrls.addAll(newUrls);
    _preloadTotalCount += newUrls.length;

    if (!_isPreloadWorkerRunning) {
      _runPreloadWorker();
    }
  });
}

Future<void> _runPreloadWorker() async {
  if (_isPreloadWorkerRunning) return;
  _isPreloadWorkerRunning = true;

  final cacheManager = PrivateImageCache();
  final lease = await TransferKeepAlive.acquire(
    title: 'Diptych 照片缓存',
    content: '正在缓存照片...',
  );
  try {
    while (_pendingPreloadUrls.isNotEmpty) {
      // Do not put the whole diary ahead of a user's explicit original request.
      final currentBatch = _pendingPreloadUrls
          .take(PrivateImageCache.maxConcurrentDownloads)
          .toList();
      _pendingPreloadUrls.removeAll(currentBatch);
      _inFlightPreloadUrls.addAll(currentBatch);

      await lease.update(
        title: 'Diptych 照片缓存',
        content: '正在缓存照片 ($_preloadDoneCount/$_preloadTotalCount)...',
        maxProgress: _preloadTotalCount,
        progress: _preloadDoneCount,
      );

      // 整批入队，PrivateImageCache 默认仅拉取预览图，最多 6 个并发。
      await Future.wait(
        currentBatch.map((url) async {
          try {
            await cacheManager.getSingleFile(url);
          } catch (_) {
          } finally {
            _inFlightPreloadUrls.remove(url);
            _preloadDoneCount++;
            await lease.update(
              title: 'Diptych 照片缓存',
              content: '正在缓存照片 ($_preloadDoneCount/$_preloadTotalCount)...',
              maxProgress: _preloadTotalCount,
              progress: _preloadDoneCount,
            );
          }
        }),
      );
    }
  } finally {
    _isPreloadWorkerRunning = false;
    _preloadTotalCount = 0;
    _preloadDoneCount = 0;
    _pendingPreloadUrls.clear();
    _inFlightPreloadUrls.clear();
    await lease.release();
  }
}

/// 解析动态列表，分出自己和对方的
Map<String, Moment?> _splitMoments(
  List<Moment> moments,
  String myUid,
  String partnerUid,
) {
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
final FutureProvider<Map<String, Moment?>> dayMomentsProvider =
    FutureProvider<Map<String, Moment?>>((ref) async {
      final selectedDate = ref.watch(selectedDateProvider);
      final dateStr = DateHelper.toDateStr(selectedDate);
      final currentUser = ref.watch(currentUserProvider);
      final partner = ref.watch(partnerUserProvider);

      if (currentUser == null || partner == null) {
        return {'myMoment': null, 'partnerMoment': null};
      }

      // 加载缓存（null = 从未请求过该日期，[] = 请求过但无数据）
      final cacheVersion = CacheService.dayVersion(dateStr);
      final cached = await CacheService.loadDayMoments(dateStr);
      if (!ref.mounted) return {'myMoment': null, 'partnerMoment': null};

      if (cached != null) {
        // 缓存命中（包括空数据）→ 秒返，后台静默刷新
        // 后台拉取最新（不阻塞，有变化才刷新 UI）
        final apiService = ref.read(apiServiceProvider);
        final oldJson = jsonEncode(cached);
        final selfRef = ref;
        apiService
            .getDayMoments(dateStr, [currentUser.uid, partner.uid])
            .then((moments) async {
              if (!selfRef.mounted ||
                  CacheService.dayVersion(dateStr) != cacheVersion) {
                return;
              }
              final newRaw = moments.map((m) => m.toJson()).toList();
              if (jsonEncode(newRaw) != oldJson) {
                await CacheService.saveDayMoments(dateStr, newRaw);
                if (!selfRef.mounted) return;
                preloadDayImages(moments);
                await syncMarkedDatesFromMoments(selfRef, dateStr, moments);
                selfRef.invalidate(dayMomentsProvider);
              } else {
                await syncMarkedDatesFromMoments(selfRef, dateStr, moments);
              }
            })
            .catchError((_) {});

        if (cached.isEmpty) return {'myMoment': null, 'partnerMoment': null};
        final moments = cached.map((e) => Moment.fromJson(e)).toList();
        preloadDayImages(moments);
        syncMarkedDatesFromMoments(ref, dateStr, moments);
        return _splitMoments(moments, currentUser.uid, partner.uid);
      }

      // 从未请求过 → 等网络（仅首次）
      final apiService = ref.read(apiServiceProvider);
      final moments = await apiService.getDayMoments(dateStr, [
        currentUser.uid,
        partner.uid,
      ]);
      if (!ref.mounted || CacheService.dayVersion(dateStr) != cacheVersion) {
        final latest = await CacheService.loadDayMoments(dateStr) ?? [];
        return _splitMoments(
          latest.map(Moment.fromJson).toList(),
          currentUser.uid,
          partner.uid,
        );
      }
      // 即使空也保存，下次秒开
      await CacheService.saveDayMoments(
        dateStr,
        moments.map((m) => m.toJson()).toList(),
      );
      preloadDayImages(moments);
      await syncMarkedDatesFromMoments(ref, dateStr, moments);
      return _splitMoments(moments, currentUser.uid, partner.uid);
    });

/// 指定日期的共写日记。
///
/// family 必须自动释放：离开日期再回来时要重新核对服务端，不能在整个进程中
/// 永久复用旧 revision。已有共记可先显示缓存再后台刷新；cached-null 不能直接
/// 当成最终结论，否则另一台设备刚切换共记时本机仍会误入旧双联编辑。
final sharedMomentProvider = FutureProvider.autoDispose
    .family<SharedMoment?, String>(_loadSharedMoment);

Future<SharedMoment?> _loadSharedMoment(Ref ref, String dateStr) async {
  final cacheVersion = CacheService.sharedMomentVersion(dateStr);
  final cached = await CacheService.loadSharedMoment(dateStr);
  if (!ref.mounted) return null;

  final cachedMoment = cached.moment;
  if (cached.isCached && cachedMoment != null) {
    preloadSharedMomentImages(cachedMoment);

    final oldJson = jsonEncode(cachedMoment.toJson());
    final apiService = ref.read(apiServiceProvider);
    unawaited(
      (() async {
        try {
          final latest = await apiService.getSharedMoment(dateStr);
          if (!ref.mounted ||
              CacheService.sharedMomentVersion(dateStr) != cacheVersion) {
            return;
          }
          final changed = jsonEncode(latest?.toJson()) != oldJson;
          if (changed) {
            await CacheService.saveSharedMoment(dateStr, latest);
          }
          if (!ref.mounted) return;
          if (latest != null) preloadSharedMomentImages(latest);
          await syncMarkedDateFromSharedMoment(ref, dateStr, latest);
          if (changed && ref.mounted) {
            ref.invalidate(sharedMomentProvider(dateStr));
          }
        } catch (_) {
          // 缓存已经可用，后台刷新失败不打断离线阅读。
        }
      })(),
    );

    return cachedMoment;
  }

  final latest = await ref.read(apiServiceProvider).getSharedMoment(dateStr);
  if (!ref.mounted ||
      CacheService.sharedMomentVersion(dateStr) != cacheVersion) {
    return (await CacheService.loadSharedMoment(dateStr)).moment;
  }
  await CacheService.saveSharedMoment(dateStr, latest);
  if (latest != null) preloadSharedMomentImages(latest);
  await syncMarkedDateFromSharedMoment(ref, dateStr, latest);
  return latest;
}

/// 日历标记数据（纯本地缓存优先；仅首次无缓存时调一次 API）
final FutureProvider<CalendarMarkedDates> markedDatesProvider =
    FutureProvider<CalendarMarkedDates>((ref) async {
      final cachedA = await CacheService.loadMarkedDates('A');
      final cachedB = await CacheService.loadMarkedDates('B');
      final cachedShared = await CacheService.loadSharedMomentDates();

      if (cachedA != null && cachedB != null && cachedShared != null) {
        // 缓存命中（包括空数据）→ 秒返
        return _mergeSharedCalendarDates(cachedA, cachedB, cachedShared);
      }

      // 首次使用 / 缓存缺失 → 从后端拉取全量
      final apiService = ref.read(apiServiceProvider);
      final (legacyResult, sharedResult) = await (
        _capture(apiService.getCalendarDates()),
        _capture(apiService.getSharedMomentDates()),
      ).wait;
      final map = legacyResult.value;
      final sharedDates = sharedResult.value;
      if (map != null) {
        final listA = map['A'] ?? [];
        final listB = map['B'] ?? [];
        await CacheService.overwriteAllCalendarDates(listA, listB);
      }
      if (sharedDates != null) {
        await CacheService.saveSharedMomentDates(sharedDates);
      }
      return _mergeSharedCalendarDates(
        map?['A'] ?? cachedA ?? const [],
        map?['B'] ?? cachedB ?? const [],
        sharedDates ?? cachedShared ?? const [],
      );
    });

CalendarMarkedDates _mergeSharedCalendarDates(
  List<String> datesA,
  List<String> datesB,
  List<String> sharedDates,
) {
  return CalendarMarkedDates(
    userADates: {...datesA, ...sharedDates},
    userBDates: {...datesB, ...sharedDates},
  );
}

/// 从某天日记列表中纯本地同步日历标记（0 网络开销，保证日记与日历强一致）
Future<void> syncMarkedDatesFromMoments(
  Ref ref,
  String dateStr,
  List<Moment> moments,
) async {
  final hasA = moments.any((m) => m.authorId == 'A');
  final hasB = moments.any((m) => m.authorId == 'B');

  bool changed = false;
  if (hasA) {
    final cachedA = await CacheService.loadMarkedDates('A') ?? [];
    if (!cachedA.contains(dateStr)) {
      cachedA.add(dateStr);
      cachedA.sort();
      await CacheService.saveMarkedDates('A', cachedA);
      changed = true;
    }
  }
  if (hasB) {
    final cachedB = await CacheService.loadMarkedDates('B') ?? [];
    if (!cachedB.contains(dateStr)) {
      cachedB.add(dateStr);
      cachedB.sort();
      await CacheService.saveMarkedDates('B', cachedB);
      changed = true;
    }
  }

  if (changed) {
    if (!ref.mounted) return;
    ref.invalidate(markedDatesProvider);
  }
}

/// 用单日共写结果修正已经存在的全量共写日期缓存。
///
/// 缓存尚未建立时不能用单日结果冒充全量数据；此时 markedDatesProvider
/// 会调用独立的 dates 接口完成首次同步。
Future<void> syncMarkedDateFromSharedMoment(
  Ref ref,
  String dateStr,
  SharedMoment? moment,
) async {
  final cached = await CacheService.loadSharedMomentDates();
  if (cached == null) return;
  final dates = cached.toSet();
  final changed = moment == null ? dates.remove(dateStr) : dates.add(dateStr);
  if (!changed) return;
  final sorted = dates.toList()..sort();
  await CacheService.saveSharedMomentDates(sorted);
  if (ref.mounted) ref.invalidate(markedDatesProvider);
}

/// 联网强制拉取所有日期的日记情况并全量覆盖本地缓存（全局刷新或弹窗手动刷新专用）
Future<void> syncCalendarMarkedDatesFromNetwork(
  WidgetRef ref, {
  bool throwOnError = false,
}) async {
  try {
    final apiService = ref.read(apiServiceProvider);
    final (legacyResult, sharedResult) = await (
      _capture(apiService.getCalendarDates()),
      _capture(apiService.getSharedMomentDates()),
    ).wait;
    final map = legacyResult.value;
    final sharedDates = sharedResult.value;
    if (map != null) {
      await CacheService.overwriteAllCalendarDates(
        map['A'] ?? const [],
        map['B'] ?? const [],
      );
    }
    if (sharedDates != null) {
      await CacheService.saveSharedMomentDates(sharedDates);
    }
    if (!ref.context.mounted) return;
    ref.invalidate(markedDatesProvider);
    final error = legacyResult.error ?? sharedResult.error;
    if (throwOnError && error != null) throw error;
  } catch (e) {
    if (throwOnError) rethrow;
  }
}

/// 保存后更新日历标记：本地缓存追加当天日期（纯本地增量更新，不调 API）
Future<void> updateMarkedDateCache(WidgetRef ref) async {
  final currentUser = ref.read(currentUserProvider);
  if (currentUser == null) return;

  final dateStr = DateHelper.toDateStr(ref.read(selectedDateProvider));
  final targetUid = currentUser.uid.isNotEmpty ? currentUser.uid : 'A';
  final cached = await CacheService.loadMarkedDates(targetUid) ?? [];
  if (!cached.contains(dateStr)) {
    cached.add(dateStr);
    cached.sort();
    await CacheService.saveMarkedDates(targetUid, cached);
  }
  if (!ref.context.mounted) return;
  ref.invalidate(markedDatesProvider);
}
