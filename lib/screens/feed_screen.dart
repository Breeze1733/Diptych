import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../providers/selected_date_provider.dart';
import '../services/cache_service.dart';
import '../services/update_service.dart';
import '../utils/date_helper.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/date_header.dart';
import '../widgets/day_split_view.dart';
import 'edit_moment_screen.dart';
import 'profile_screen.dart';
import 'topics_screen.dart';

/// 是否已静默检查过更新（仅触发一次）
final _autoUpdateCheckedProvider = StateProvider<bool>((ref) => false);

/// 主页面：顶栏 + 日视图分屏 + FAB
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final currentUser = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);

    // 确保用户数据已加载
    final loadUsersAsync = ref.watch(loadUsersProvider);

    // 用户数据加载完成后，静默检查更新（仅一次）
    final hasChecked = ref.watch(_autoUpdateCheckedProvider);
    if (!hasChecked && loadUsersAsync is AsyncData) {
      ref.read(_autoUpdateCheckedProvider.notifier).state = true;
      _silentCheckUpdate(context);
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(AppStrings.appTitle),
        actions: [
          // 话题
          IconButton(
            icon: const Icon(Icons.forum_outlined, size: 20),
            tooltip: '话题',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopicsScreen())),
          ),
          // 刷新按钮
          _buildRefreshButton(ref),
          // 个人设置
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '个人设置',
            onPressed: () => _openProfile(context),
          ),
        ],
      ),
      body: _buildBody(ref, loadUsersAsync, currentUser, partner, selectedDate, context),
      // FAB 仅在没有自己的动态时显示（用于新建）
      floatingActionButton: _buildFabIfNeeded(ref, currentUser, context),
    );
  }

  /// 刷新按钮（后端离线时禁用）
  Widget _buildRefreshButton(WidgetRef ref) {
    final online = ref.watch(backendOnlineProvider);
    final isLoading = ref.watch(dayMomentsProvider).isLoading;
    return IconButton(
      icon: isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.refresh, size: 20, color: online ? Colors.grey[700] : Colors.grey[400]),
      tooltip: '刷新',
      onPressed: (online && !isLoading) ? () => refreshDayData(ref) : null,
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
        final myMoment = data['myMoment'];
        final partnerMoment = data['partnerMoment'];
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
              ? () => _openCommentDialog(context, ref, partnerMoment, null)
              : null,
          // 删除自己动态下的评论
          onDeleteMyComment: myMoment != null
              ? (c) => _deleteComment(context, ref, myMoment, c)
              : null,
          onDeletePartnerComment: partnerMoment != null
              ? (c) => _deleteComment(context, ref, partnerMoment, c)
              : null,
          // 回复评论
          onReplyMyComment: myMoment != null
              ? (parent) => _openCommentDialog(context, ref, myMoment, parent)
              : null,
          onReplyPartnerComment: partnerMoment != null
              ? (parent) => _openCommentDialog(context, ref, partnerMoment, parent)
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

  /// 生成评论 ID
  String _makeCommentId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// 打开评论弹窗（新增 / 回复）
  Future<void> _openCommentDialog(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
    Comment? replyTo, // null = 新增顶级评论，非 null = 回复某条
  ) async {
    final controller = TextEditingController();
    final title = replyTo != null ? '回复评论' : AppStrings.commentTitle;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: replyTo != null ? '写下回复...' : AppStrings.commentHint,
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
      final currentUser = ref.read(currentUserProvider);
      final newComment = Comment(
        id: _makeCommentId(),
        authorId: currentUser?.uid ?? '',
        content: result,
        replyTo: replyTo?.id, // 如果是回复，记录父评论 id
        createdAt: DateTime.now(),
      );

      final newComments = List<Comment>.from(moment.comments);

      if (replyTo != null) {
        // 回复：插入到父评论的正下方（找到父评论后面所有同父评论之后）
        int insertIndex = newComments.indexWhere((c) => c.id == replyTo.id);
        if (insertIndex != -1) {
          // 跳过父评论及其已有的所有子回复
          insertIndex++;
          while (insertIndex < newComments.length &&
              newComments[insertIndex].replyTo == replyTo.id) {
            insertIndex++;
          }
          newComments.insert(insertIndex, newComment);
        } else {
          newComments.add(newComment);
        }
      } else {
        // 顶级评论：追加到末尾
        newComments.add(newComment);
      }

      final apiService = ref.read(apiServiceProvider);
      try {
        await apiService.updateMoment(moment.id, {
          'comments': newComments.map((c) => c.toJson()).toList(),
        });
        // 立即更新本地缓存，确保刷新后读到最新数据
        await _updateCachedMomentComments(ref, moment.id, newComments);
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

  /// 更新本地缓存中某条日记的评论
  Future<void> _updateCachedMomentComments(WidgetRef ref, String momentId, List<Comment> comments) async {
    final dateStr = DateHelper.toDateStr(ref.read(selectedDateProvider));
    final cached = await CacheService.loadDayMoments(dateStr);
    if (cached == null) return;
    for (int i = 0; i < cached.length; i++) {
      if (cached[i]['id'] == momentId) {
        cached[i]['comments'] = comments.map((c) => c.toJson()).toList();
        break;
      }
    }
    await CacheService.saveDayMoments(dateStr, cached);
  }

  /// 删除评论（同时删除其所有子回复）
  Future<void> _deleteComment(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
    Comment comment,
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

    // 收集要删除的评论 id（包括子回复）
    final toRemove = <String>{comment.id};
    // 找出所有回复该评论的子评论
    for (final c in moment.comments) {
      if (c.replyTo == comment.id) toRemove.add(c.id);
    }

    final newComments = moment.comments.where((c) => !toRemove.contains(c.id)).toList();

    final apiService = ref.read(apiServiceProvider);
    try {
      await apiService.updateMoment(moment.id, {
        'comments': newComments.map((c) => c.toJson()).toList(),
      });
      // 立即更新本地缓存
      await _updateCachedMomentComments(ref, moment.id, newComments);
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 刷新数据（触发后端拉取 + 本地更新日历圆点）
  void _refresh(WidgetRef ref) {
    refreshDayData(ref);
    updateMarkedDateCache(ref);
  }

  /// 打开个人设置
  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  /// 静默检查更新（后端不通不报错）
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

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text('最新版本 ${latest.version}，是否更新？\n\n${latest.releaseNotes}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.cancel, style: TextStyle(color: Colors.grey[600])),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: Text(AppStrings.confirm),
            ),
          ],
        ),
      );

      if (ok == true) {
        final apkPath = await service.downloadApk(latest.downloadUrl, (_) {});
        await service.installApk(apkPath);
        await service.markForCleanup(apkPath);
      }
      service.dispose();
    } catch (_) {
      // 后端不通，静默跳过
    }
  }

}
