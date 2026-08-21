import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';
import 'api_service.dart';

/// 本地通知持久化与中转队列同步服务
class NotificationService {
  static const _prefix = 'cached_notifications_';

  /// 读取本地保存的通知列表（按时间倒序）
  static Future<List<AppNotification>> loadLocalNotifications(String userId) async {
    if (userId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$userId');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final notifs = list
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      notifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifs;
    } catch (_) {
      return [];
    }
  }

  /// 保存通知列表到本地
  static Future<void> saveLocalNotifications(
      String userId, List<AppNotification> list) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonList = list.map((e) => e.toJson()).toList();
    await prefs.setString('$_prefix$userId', jsonEncode(jsonList));
  }

  /// 同步服务端待读队列（拉取 ➔ 合并入本地持久化）
  static Future<List<AppNotification>> sync(
      String userId, ApiService api) async {
    if (userId.isEmpty) return [];
    final localList = await loadLocalNotifications(userId);

    // 1. 从服务端拉取待读通知（服务端在读取时已自动清空该批队列）
    final pending = await api.getPendingNotifications(userId);
    if (pending.isEmpty) return localList;

    // 2. 合并入本地列表（若 ID 已存在则原地更新内容，新 ID 则以未读状态追加到最前）
    final existingMap = {for (final n in localList) n.id: n};
    for (final p in pending) {
      if (existingMap.containsKey(p.id)) {
        existingMap[p.id] = p.copyWith(isRead: existingMap[p.id]!.isRead);
      } else {
        existingMap[p.id] = p.copyWith(isRead: false);
      }
    }

    final merged = existingMap.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 3. 成功持久化到本地
    await saveLocalNotifications(userId, merged);

    return merged;
  }

  /// 标记单条通知为已读
  static Future<List<AppNotification>> markAsRead(
      String userId, String notificationId) async {
    final list = await loadLocalNotifications(userId);
    final updated = list.map((n) {
      if (n.id == notificationId) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    await saveLocalNotifications(userId, updated);
    return updated;
  }

  /// 全部标记为已读
  static Future<List<AppNotification>> markAllAsRead(String userId) async {
    final list = await loadLocalNotifications(userId);
    final updated = list.map((n) => n.copyWith(isRead: true)).toList();
    await saveLocalNotifications(userId, updated);
    return updated;
  }

  /// 清空本地所有通知
  static Future<void> clearAll(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$userId');
  }
}
