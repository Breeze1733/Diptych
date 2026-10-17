import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/moment.dart';

/// 本地缓存服务 —— 离线也能看日记
class CacheService {
  static const _prefixDay = 'cache_day_';
  static const _prefixMarked = 'cache_marked_';
  static const _prefixUser = 'cache_user_';
  static final _dayVersions = <String, int>{};

  static int dayVersion(String dateStr) => _dayVersions[dateStr] ?? 0;

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
