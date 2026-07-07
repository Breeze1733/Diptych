import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../providers/selected_date_provider.dart';
import '../utils/date_helper.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/date_header.dart';
import '../widgets/day_split_view.dart';
import 'edit_moment_screen.dart';
import 'profile_screen.dart';

/// 主页面：顶栏 + 日视图分屏 + FAB
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final currentUser = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final role = ref.watch(currentUserRoleProvider);

    // 确保用户数据已加载
    final loadUsersAsync = ref.watch(loadUsersProvider);

    // 用户显示名：优先从加载的数据取，否则用角色生成
    final displayName = currentUser?.nickname ?? (role != null ? '用户$role' : '');

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(AppStrings.appTitle),
        actions: [
          // 显示当前登录用户
          if (displayName.isNotEmpty)
            Chip(
              avatar: const Icon(Icons.person, size: 16),
              label: Text(displayName),
              backgroundColor: AppTheme.primaryColor.withAlpha(20),
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          // 个人设置
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '个人设置',
            onPressed: () => _openProfile(context),
          ),
          // 退出按钮
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: AppStrings.logout,
            onPressed: () => _handleLogout(ref),
          ),
        ],
      ),
      body: _buildBody(ref, loadUsersAsync, currentUser, partner, selectedDate, context),
      // FAB 仅在没有自己的动态时显示（用于新建）
      floatingActionButton: _buildFabIfNeeded(ref, currentUser, context),
    );
  }

  /// 仅在自己的动态为空时显示绿色新建按钮
  Widget? _buildFabIfNeeded(WidgetRef ref, currentUser, BuildContext context) {
    if (currentUser == null) return null;

    final dayMomentsAsync = ref.watch(dayMomentsProvider);
    return dayMomentsAsync.when(
      data: (data) {
        final myMoment = data['myMoment'];
        // 已有动态就不显示 FAB（编辑在卡片内操作）
        if (myMoment != null) return null;
        return FloatingActionButton.extended(
          onPressed: () => _openCreateEditor(ref, context),
          icon: const Icon(Icons.add),
          label: const Text(AppStrings.createTitle),
        );
      },
      loading: () => null,
      error: (_, _) => null,
    );
  }

  Widget _buildBody(WidgetRef ref, AsyncValue<void> loadUsersAsync,
      currentUser, partner, DateTime selectedDate, BuildContext context) {
    if (loadUsersAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loadUsersAsync.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '加载失败：${loadUsersAsync.error}\n\n请检查后端服务是否正常运行',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (currentUser == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '用户数据加载失败\n\n请确认后端已实现以下接口：\n• POST /api/users/ensure\n• GET /api/users/:uid',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        DateHeader(
          dateText: DateHelper.toChineseDate(selectedDate),
          onCalendarTap: () => _openCalendar(context, ref),
        ),
        const Divider(height: 1, thickness: 1, color: AppTheme.dividerColor),
        if (currentUser != null && partner != null)
          _buildDayView(ref, currentUser, partner, context),
      ],
    );
  }

  /// 构建日视图
  Widget _buildDayView(WidgetRef ref, currentUser, partner, BuildContext context) {
    final dayMomentsAsync = ref.watch(dayMomentsProvider);

    return dayMomentsAsync.when(
      data: (data) {
        final myMoment = data['myMoment'] as Moment?;
        final partnerMoment = data['partnerMoment'] as Moment?;
        return DaySplitView(
          myMoment: myMoment,
          partnerMoment: partnerMoment,
          myNickname: currentUser.nickname,
          partnerNickname: partner.nickname,
          myAvatarUrl: currentUser.avatarUrl,
          partnerAvatarUrl: partner.avatarUrl,
          // 编辑自己的动态
          onEditMyMoment: myMoment != null
              ? () => _openEditor(
                    context,
                    ref,
                    ref.read(selectedDateProvider),
                    myMoment,
                  )
              : null,
          // 评论对方的动态
          onCommentPartner: partnerMoment != null
              ? () => _openCommentDialog(
                    context,
                    ref,
                    partnerMoment,
                  )
              : null,
          // 删除自己动态下的评论
          onDeleteMyComment: myMoment != null
              ? (index) => _deleteComment(context, ref, myMoment, index)
              : null,
          onDeletePartnerComment: partnerMoment != null
              ? (index) => _deleteComment(context, ref, partnerMoment, index)
              : null,
        );
      },
      loading: () => const Expanded(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Expanded(
        child: Center(child: Text('加载失败: $e')),
      ),
    );
  }

  /// 打开日历选择器
  Future<void> _openCalendar(BuildContext context, WidgetRef ref) async {
    final markedDatesAsync = ref.read(markedDatesProvider);
    final markedDates = markedDatesAsync.valueOrNull ?? [];

    final picked = await CalendarPicker.show(
      context,
      selectedDate: ref.read(selectedDateProvider),
      markedDates: markedDates,
    );

    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
    }
  }

  /// 打开新建编辑页
  Future<void> _openCreateEditor(WidgetRef ref, BuildContext context) async {
    final date = ref.read(selectedDateProvider);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditMomentScreen(date: date),
      ),
    );
    if (result == true) {
      _refresh(ref);
    }
  }

  /// 打开编辑页
  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    Moment existingMoment,
  ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditMomentScreen(
          date: date,
          existingMoment: existingMoment,
        ),
      ),
    );
    if (result == true) {
      _refresh(ref);
    }
  }

  /// 打开评论弹窗
  Future<void> _openCommentDialog(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.commentTitle),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: AppStrings.commentHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel, style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: Text(AppStrings.confirm),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final apiService = ref.read(apiServiceProvider);
      final newComments = List<String>.from(moment.comments)..add(result);
      try {
        await apiService.updateMoment(moment.id, {'comments': newComments});
        _refresh(ref);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('评论失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 删除评论
  Future<void> _deleteComment(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.deleteComment),
        content: const Text(AppStrings.deleteCommentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.cancel, style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(AppStrings.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final apiService = ref.read(apiServiceProvider);
    final newComments = List<String>.from(moment.comments)..removeAt(index);
    try {
      await apiService.updateMoment(moment.id, {'comments': newComments});
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 刷新数据
  void _refresh(WidgetRef ref) {
    ref.invalidate(dayMomentsProvider);
    ref.invalidate(markedDatesProvider);
  }

  /// 打开个人设置
  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  /// 退出登录
  void _handleLogout(WidgetRef ref) {
    final logout = ref.read(logoutActionProvider);
    logout();
  }
}
