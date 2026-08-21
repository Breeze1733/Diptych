import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// 通知列表状态管理 Notifier
class NotificationListNotifier extends Notifier<List<AppNotification>> {
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

  /// 与后端队列静默同步
  Future<void> sync() async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    final api = ref.read(apiServiceProvider);
    try {
      final updated = await NotificationService.sync(role, api);
      state = updated;
    } catch (_) {}
  }

  /// 标记单条通知已读
  Future<void> markAsRead(String id) async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    final updated = await NotificationService.markAsRead(role, id);
    state = updated;
  }

  /// 全部标记为已读
  Future<void> markAllAsRead() async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    final updated = await NotificationService.markAllAsRead(role);
    state = updated;
  }

  /// 清空本地所有通知
  Future<void> clearAll() async {
    final role = ref.read(currentUserRoleProvider);
    if (role == null) return;
    await NotificationService.clearAll(role);
    state = const [];
  }
}

final notificationListProvider =
    NotifierProvider<NotificationListNotifier, List<AppNotification>>(
        NotificationListNotifier.new);

/// 未读通知总数 Provider（用于驱动顶栏 Badge）
final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationListProvider);
  return list.where((n) => !n.isRead).length;
});
