import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/app_notification.dart';
import '../providers/notification_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../utils/date_helper.dart';
import '../widgets/wallpaper_layer.dart';
import 'topic_detail_screen.dart';

/// 动态信箱页面
class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // 进入信箱页面时静默同步一次队列
    Future.microtask(() {
      ref.read(notificationListProvider.notifier).sync();
    });
  }

  Future<void> _handleRefresh() async {
    await ref.read(notificationListProvider.notifier).sync();
  }

  Future<void> _handleMarkAllAsRead(int unreadCount) async {
    if (unreadCount == 0) return;
    await ref.read(notificationListProvider.notifier).markAllAsRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已全部标记为已读'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleClearAll(int totalCount) async {
    if (totalCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空信箱'),
        content: const Text('确定清空所有动态通知吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(notificationListProvider.notifier).clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('信箱已清空'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _handleItemTap(AppNotification notif) {
    // 1. 本地标记已读
    if (!notif.isRead) {
      ref.read(notificationListProvider.notifier).markAsRead(notif.id);
    }

    // 2. 根据类型跳转
    if (notif.type == AppNotificationType.moment ||
        notif.type == AppNotificationType.momentComment) {
      if (notif.dateStr != null && notif.dateStr!.isNotEmpty) {
        try {
          final targetDate = DateHelper.parseDateStr(notif.dateStr!);
          ref.read(selectedDateProvider.notifier).setDate(targetDate);
          Navigator.pop(context); // 回到日记主页
        } catch (_) {}
      }
    } else if (notif.type == AppNotificationType.topicPost ||
        notif.type == AppNotificationType.topicCreated) {
      if (notif.topicId != null && notif.topicId!.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailScreen(topicId: notif.topicId!),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationListProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final wallpaper = ref.watch(wallpaperSettingsProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(
          url: wallpaper.diaryUrl,
          opacity: wallpaper.diaryOpacity,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: const Text('信箱'),
            actions: [
              // 全部已读按钮
              IconButton(
                icon: const Icon(Icons.done_all_outlined, size: 22),
                tooltip: '全部已读',
                onPressed: list.isEmpty || unreadCount == 0
                    ? null
                    : () => _handleMarkAllAsRead(unreadCount),
              ),
              // 清空信箱按钮
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 22),
                tooltip: '清空信箱',
                onPressed: list.isEmpty
                    ? null
                    : () => _handleClearAll(list.length),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _handleRefresh,
            child: list.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      return _buildNotificationCard(item);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: AppTheme.selfColor,
              ),
              const SizedBox(height: 16),
              const Text(
                '信箱空空如也',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '对方发布日记、评论或发帖时\n会在这里显示',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 单条通知卡片
  Widget _buildNotificationCard(AppNotification notif) {
    // 视觉色彩配置
    IconData iconData;

    switch (notif.type) {
      case AppNotificationType.moment:
        iconData = Icons.calendar_today_outlined;
        break;
      case AppNotificationType.momentComment:
        iconData = Icons.chat_bubble_outline;
        break;
      case AppNotificationType.topicPost:
      case AppNotificationType.topicCreated:
        iconData = Icons.forum_outlined;
        break;
    }

    return Material(
      color: AppTheme.surfaceColor.withAlpha(235),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleItemTap(notif),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 类型图标
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.softSurface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(iconData, size: 20, color: AppTheme.selfColor),
              ),
              const SizedBox(width: 12),
              // 正文内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: notif.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        // 陶土色圆点是唯一的未读强调
                        if (!notif.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (notif.content.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        notif.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // 时间
                    Text(
                      DateHelper.toFriendlyDateTime(notif.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
