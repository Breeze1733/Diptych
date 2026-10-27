import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/moment.dart';
import '../models/shared_moment.dart';

class SharedMomentCacheEntry {
  final bool isCached;
  final SharedMoment? moment;

  const SharedMomentCacheEntry._({
    required this.isCached,
    required this.moment,
  });

  const SharedMomentCacheEntry.uncached()
    : this._(isCached: false, moment: null);

  const SharedMomentCacheEntry.cached(SharedMoment? moment)
    : this._(isCached: true, moment: moment);
}

/// 本地缓存服务 —— 离线也能看日记
class CacheService {
  static const _prefixDay = 'cache_day_';
  static const _prefixSharedDay = 'cache_shared_day_';
  static const _prefixMarked = 'cache_marked_';
  static const _sharedMarkedKey = 'cache_shared_marked_dates';
  static const _prefixUser = 'cache_user_';
  static final _dayVersions = <String, int>{};
  static final _sharedDayVersions = <String, int>{};

  static int dayVersion(String dateStr) => _dayVersions[dateStr] ?? 0;

  static int sharedMomentVersion(String dateStr) =>
      _sharedDayVersions[dateStr] ?? 0;

  // ─── 日记缓存 ───

  static Future<void> saveDayMoments(
    String dateStr,
    List<Map<String, dynamic>> raw,
  ) async {
    _dayVersions[dateStr] = dayVersion(dateStr) + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixDay$dateStr', jsonEncode(raw));
  }

  /// 先使旧的后台请求失效，再按日记自己的日期更新缓存，保留另一人的日记。
  static Future<void> saveMoment(Moment moment) async {
    final dateStr = moment.dateStr;
    _dayVersions[dateStr] = dayVersion(dateStr) + 1;
    final cached = await loadDayMoments(dateStr) ?? [];
    final index = cached.indexWhere(
      (raw) =>
          raw['id']?.toString() == moment.id ||
          (raw['date_str'] == dateStr && raw['author_id'] == moment.authorId),
    );
    if (index < 0) {
      cached.add(moment.toJson());
    } else {
      cached[index] = moment.toJson();
    }
    await saveDayMoments(dateStr, cached);
  }

  static Future<List<Map<String, dynamic>>?> loadDayMoments(
    String dateStr,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixDay$dateStr');
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  // ─── 共写日记缓存 ───

  /// 写入 null 也代表一次有效的网络结果，避免空日期每次进入都阻塞等网。
  static Future<void> saveSharedMoment(
    String dateStr,
    SharedMoment? moment,
  ) async {
    _sharedDayVersions[dateStr] = sharedMomentVersion(dateStr) + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefixSharedDay$dateStr',
      jsonEncode(moment?.toJson()),
    );

    // 只有全量 dates 缓存已经存在时才做单日增量修正；否则不能用一个
    // 日期冒充全量结果，markedDatesProvider 会负责首次联网同步。
    final rawDates = prefs.getString(_sharedMarkedKey);
    if (rawDates != null) {
      try {
        final dates = (jsonDecode(rawDates) as List)
            .map((value) => value.toString())
            .toSet();
        final changed = moment == null
            ? dates.remove(dateStr)
            : dates.add(dateStr);
        if (changed) {
          final sorted = dates.toList()..sort();
          await prefs.setString(_sharedMarkedKey, jsonEncode(sorted));
        }
      } catch (_) {
        // 损坏的 dates 缓存留给全量同步覆盖，不写入不完整列表。
      }
    }
  }

  /// [SharedMomentCacheEntry.uncached] 与 cached(null) 含义不同。
  static Future<SharedMomentCacheEntry> loadSharedMoment(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixSharedDay$dateStr');
    if (raw == null) return const SharedMomentCacheEntry.uncached();
    try {
      final decoded = jsonDecode(raw);
      if (decoded == null) return const SharedMomentCacheEntry.cached(null);
      if (decoded is! Map) return const SharedMomentCacheEntry.uncached();
      return SharedMomentCacheEntry.cached(
        SharedMoment.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } catch (_) {
      // 损坏的缓存等同未缓存，让调用方重新从服务端获取。
      return const SharedMomentCacheEntry.uncached();
    }
  }

  // ─── 标记日期缓存（日历双人状态）───

  /// 全量覆盖保存双人日历标记
  static Future<void> overwriteAllCalendarDates(
    List<String> datesA,
    List<String> datesB,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefixMarked}A', jsonEncode(datesA));
    await prefs.setString('${_prefixMarked}B', jsonEncode(datesB));
  }

  static Future<void> saveMarkedDates(String userId, List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixMarked$userId', jsonEncode(dates));
  }

  static Future<List<String>?> loadMarkedDates(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixMarked$userId');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSharedMomentDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sharedMarkedKey, jsonEncode(dates));
  }

  static Future<List<String>?> loadSharedMomentDates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sharedMarkedKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((value) => value.toString())
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ─── 用户信息缓存 ───

  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixUser${user.uid}', jsonEncode(user.toJson()));
  }

  static Future<AppUser?> loadUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixUser$uid');
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
