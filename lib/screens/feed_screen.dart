import "dart:math" as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/selected_date_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/update_service.dart';
import '../utils/date_helper.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/date_header.dart';
import '../widgets/day_split_view.dart';
import '../widgets/wallpaper_layer.dart';
import 'edit_moment_screen.dart';
import 'diary_reading_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'diary_search_screen.dart';

/// 是否已静默检查过更新（仅触发一次）
class AutoUpdateCheckedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markChecked() => state = true;
}

final _autoUpdateCheckedProvider =
    NotifierProvider<AutoUpdateCheckedNotifier, bool>(
      AutoUpdateCheckedNotifier.new,
    );

/// Diary section: quiet app chrome, date picker and the two daily entries.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final currentUser = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final loadUsersAsync = ref.watch(loadUsersProvider);
    ref.watch(markedDatesProvider);
    ref.watch(initWallpaperProvider);
    final wallpaper = ref.watch(wallpaperSettingsProvider);
    final unreadNotificationCount = ref.watch(unreadNotificationCountProvider);
    final isLoading = ref.watch(dayMomentsProvider).isLoading;
    final screenSize = MediaQuery.sizeOf(context);
    final scale = math
        .min(screenSize.width / 375, screenSize.height / 700)
        .clamp(.65, 1.0);

    final hasChecked = ref.watch(_autoUpdateCheckedProvider);
    if (!hasChecked && loadUsersAsync is AsyncData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || ref.read(_autoUpdateCheckedProvider)) return;
        ref.read(_autoUpdateCheckedProvider.notifier).markChecked();
        _silentCheckUpdate(context);
      });
    }

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
            backgroundColor: AppTheme.surfaceColor.withValues(
              alpha: wallpaper.cardOpacity,
            ),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: (kToolbarHeight * scale).clamp(44.0, 56.0),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon.png',
                  width: 28,
                  height: 28,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 9),
                const Flexible(
                  child: Text(
                    AppStrings.appTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '搜索日记',
                icon: const Icon(Icons.search_rounded, size: 22),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiarySearchScreen()),
                ),
              ),
              IconButton(
                icon: Badge(
                  backgroundColor: AppTheme.accentColor,
                  isLabelVisible: unreadNotificationCount > 0,
                  label: Text(
                    unreadNotificationCount > 99
                        ? '99+'
                        : '$unreadNotificationCount',
                    style: const TextStyle(fontSize: 11),
                  ),
                  child: const Icon(Icons.mail_outline_rounded, size: 22),
                ),
                tooltip: '信箱',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
              ),
              IconButton(
                tooltip: isLoading ? '正在刷新' : '刷新',
                onPressed: isLoading
                    ? null
                    : () {
                        ref.invalidate(dayMomentsProvider);
                        syncCalendarMarkedDatesFromNetwork(ref);
                        ref.read(notificationListProvider.notifier).sync();
                      },
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 22),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: _buildBody(
              ref,
              loadUsersAsync,
              currentUser,
              partner,
              selectedDate,
              context,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    WidgetRef ref,
    AsyncValue<void> loadUsersAsync,
    currentUser,
    partner,
    DateTime selectedDate,
    BuildContext context,
  ) {
    // 只有彻底加载失败且无用户数据才显示错误
    if (currentUser == null && loadUsersAsync.hasError) {
      debugPrint('加载用户数据失败: ${loadUsersAsync.error}');
      return _paperArea(
        ref,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  '加载用户信息失败\n请检查网络或后端服务后重试',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(loadUsersProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 始终渲染布局，数据到了自动填充（不转圈）
    return Column(
      children: [
        DateHeader(
          cardOpacity: ref.watch(wallpaperSettingsProvider).cardOpacity,
          dateText: DateHelper.toChineseDate(selectedDate),
          date: selectedDate,
          onCalendarTap: () => _openCalendar(context, ref),
          onPreviousDay: _canChangeDay(selectedDate, -1)
              ? () => _changeDay(ref, selectedDate, -1)
              : null,
          onNextDay: _canChangeDay(selectedDate, 1)
              ? () => _changeDay(ref, selectedDate, 1)
              : null,
        ),
        if (currentUser != null && partner != null)
          _buildDayView(ref, currentUser, partner, context)
        else
          Expanded(child: _paperArea(ref)),
      ],
    );
  }

  /// 非日记内容状态也铺满同一张纸面，不额外覆盖已有的双联纸页。
  Widget _paperArea(WidgetRef ref, {Widget? child}) => ColoredBox(
    color: AppTheme.surfaceColor.withValues(
      alpha: ref.watch(wallpaperSettingsProvider).cardOpacity,
    ),
    child: SizedBox.expand(child: child),
  );

  /// 构建日视图
  Widget _buildDayView(
    WidgetRef ref,
    currentUser,
    partner,
    BuildContext context,
  ) {
    final dayMomentsAsync = ref.watch(dayMomentsProvider);

    return dayMomentsAsync.when(
      skipLoadingOnRefresh: true,
      data: (data) {
        final myMoment = data['myMoment'];
        final partnerMoment = data['partnerMoment'];
        return DaySplitView(
          cardOpacity: ref.watch(wallpaperSettingsProvider).cardOpacity,
          onCreateMyMoment: () => _openCreateEditor(ref, context),
          onOpenReading: (moment) => _openReading(context, moment),
          myMoment: myMoment,
          partnerMoment: partnerMoment,
          myNickname: currentUser.nickname,
          partnerNickname: partner.nickname,
          myAvatarUrl: currentUser.avatarUrl,
          partnerAvatarUrl: partner.avatarUrl,
        );
      },
      loading: () => Expanded(child: _paperArea(ref)),
      error: (e, _) {
        debugPrint('加载日记失败: $e');
        return Expanded(
          child: _paperArea(
            ref,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    '加载失败，请检查网络后重试',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(dayMomentsProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openReading(BuildContext context, Moment moment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiaryReadingScreen(initialMoment: moment),
      ),
    );
  }

  bool _canChangeDay(DateTime selected, int delta) {
    final next = DateTime(selected.year, selected.month, selected.day + delta);
    return !next.isBefore(CalendarPicker.firstDate) &&
        !next.isAfter(CalendarPicker.lastDate);
  }

  void _changeDay(WidgetRef ref, DateTime selected, int delta) {
    if (!_canChangeDay(selected, delta)) return;
    ref
        .read(selectedDateProvider.notifier)
        .setDate(DateTime(selected.year, selected.month, selected.day + delta));
  }

  /// 打开日历选择器
  Future<void> _openCalendar(BuildContext context, WidgetRef ref) async {
    final picked = await CalendarPicker.show(
      context,
      selectedDate: ref.read(selectedDateProvider),
    );

    if (picked != null) {
      ref.read(selectedDateProvider.notifier).setDate(picked);
    }
  }

  /// 打开新建编辑页
  Future<void> _openCreateEditor(WidgetRef ref, BuildContext context) async {
    final date = ref.read(selectedDateProvider);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditMomentScreen(date: date)),
    );
    if (result == true) {
      _refresh(ref);
    }
  }

  /// 刷新数据（清除 Provider 缓存强制重读 + 更新日历圆点 + 同步信箱）
  void _refresh(WidgetRef ref) {
    ref.invalidate(dayMomentsProvider);
    updateMarkedDateCache(ref);
    syncCalendarMarkedDatesFromNetwork(ref);
    ref.read(notificationListProvider.notifier).sync();
  }

  /// 静默检查更新（后端不通不报错）。
  /// 全局提示只负责提醒 + 跳转设置页，下载入口仅在设置页提供。
  static Future<void> _silentCheckUpdate(BuildContext context) async {
    try {
      final service = UpdateService();
      final current = await service.getCurrentVersion();
      final latest = await service.checkLatestVersion();

      if (!service.needUpdate(current, latest)) {
        service.dispose();
        return;
      }

      if (!context.mounted) return;

      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
            '最新版本 ${latest.version}\n\n${latest.releaseNotes}\n\n请前往「设置」页面下载更新。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                AppStrings.cancel,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );

      if (goSettings == true) {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      }
      service.dispose();
    } catch (_) {
      // 后端不通，静默跳过
    }
  }
}
