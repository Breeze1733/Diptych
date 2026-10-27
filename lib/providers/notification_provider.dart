import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../utils/date_helper.dart';
import 'auth_provider.dart';
import 'day_moment_provider.dart';
import 'selected_date_provider.dart';

/// 通知列表状态管理 Notifier
class NotificationListNotifier extends Notifier<List<AppNotification>> {
  bool _isSyncing = false;

  @override
  List<AppNotification> build() {
    final role = ref.watch(currentUserRoleProvider);
    if (role == null) return const [];

    // 初始从本地持久化秒开，并随后触发静默同步
    Future(() async {
      final local = await NotificationService.loadLocalNotifications(role);
      state = local;
      await sync();
    });

    return const [];
  }

  /// 与后端队列静默同步（增加并发锁防抖）
  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    final role = ref.read(currentUserRoleProvider);
    if (role == null) {
      _isSyncing = false;
      return;
    }
    final api = ref.read(apiServiceProvider);
    try {
      final knownIds = state.map((item) => item.id).toSet();
      final updated = await NotificationService.sync(role, api);
      state = updated;
      final selectedDate = DateHelper.toDateStr(
        ref.read(selectedDateProvider),
      );
      for (final notification in updated) {
        if (knownIds.contains(notification.id) ||
            notification.dateStr == null) {
          continue;
        }
        if (notification.dateStr == selectedDate &&
            (notification.type == AppNotificationType.moment ||
                notification.type == AppNotificationType.momentComment)) {
          ref.invalidate(dayMomentsProvider);
        }
        if (notification.sharedMomentId?.isNotEmpty == true) {
          ref.invalidate(sharedMomentProvider(notification.dateStr!));
        }
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
  }

  /// 标记单条通知已读（带乐观更新）
  Future<void> markAsRead(String id) async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    // 乐观立即将该项标为已读
    state = state
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
    final updated = await NotificationService.markAsRead(role, id);
    state = updated;
  }

  /// 全部标记为已读（带乐观更新）
  Future<void> markAllAsRead() async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    // 乐观立即将所有项标为已读，避免网络或读取延迟引起界面无反应
    state = state.map((n) => n.copyWith(isRead: true)).toList();
    final updated = await NotificationService.markAllAsRead(role);
    state = updated;
  }

  /// 清空本地所有通知
  Future<void> clearAll() async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    state = const [];
    await NotificationService.clearAll(role);
  }
}

final notificationListProvider =
    NotifierProvider<NotificationListNotifier, List<AppNotification>>(
      NotificationListNotifier.new,
    );

/// 未读通知总数 Provider（用于驱动顶栏 Badge）
final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationListProvider);
  return list.where((n) => !n.isRead).length;
});
