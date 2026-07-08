import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/moment.dart';
import '../models/app_user.dart';

/// 本地缓存服务 —— 离线也能看日记
class CacheService {
  static const _prefixDay = 'cache_day_';
  static const _prefixMarked = 'cache_marked_';
  static const _prefixUser = 'cache_user_';
  static const _prefixAllDates = 'cache_all_dates_';

  // ─── 日记缓存 ───

  static Future<void> saveDayMoments(String dateStr, List<Map<String, dynamic>> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixDay$dateStr', jsonEncode(raw));
  }

  static Future<List<Map<String, dynamic>>?> loadDayMoments(String dateStr) async {
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

  // ─── 标记日期缓存（日历小圆点）───

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

  // ─── 全部有日记的日期缓存 ───

  static Future<void> saveAllDatesWithMoments(String userId, List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixAllDates$userId', jsonEncode(dates));
  }

  static Future<List<String>?> loadAllDatesWithMoments(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixAllDates$userId');
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
