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
import '../services/cache_service.dart';
import '../services/draft_service.dart';
import '../services/update_service.dart';
import '../utils/date_helper.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/date_header.dart';
import '../widgets/day_split_view.dart';
import '../widgets/moment_card.dart';
import '../widgets/wallpaper_layer.dart';
import 'edit_moment_screen.dart';
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

class _CommentDialogResult {
  final String content;
  final bool saveDraft;

  const _CommentDialogResult(this.content, {required this.saveDraft});
}

class _DiaryCommentDialog extends StatefulWidget {
  final String initialText;
  final bool isReply;

  const _DiaryCommentDialog({required this.initialText, required this.isReply});

  @override
  State<_DiaryCommentDialog> createState() => _DiaryCommentDialogState();
}

class _DiaryCommentDialogState extends State<_DiaryCommentDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({required bool saveDraft}) {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.pop(context, _CommentDialogResult(text, saveDraft: saveDraft));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isReply ? '回复评论' : AppStrings.commentTitle),
    content: SelectionContainer.disabled(
      child: TextField(
        controller: _controller,
        maxLines: 3,
        contextMenuBuilder: (context, editableTextState) =>
            AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: editableTextState.contextMenuButtonItems,
            ),
        decoration: InputDecoration(
          hintText: widget.isReply ? '写下回复...' : AppStrings.commentHint,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppStrings.cancel),
      ),
      TextButton(
        onPressed: () => _submit(saveDraft: true),
        child: const Text('存草稿'),
      ),
      FilledButton(
        onPressed: () => _submit(saveDraft: false),
        child: Text(AppStrings.confirm),
      ),
    ],
  );
}

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
            backgroundColor: AppTheme.surfaceColor.withAlpha(235),
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
              scale,
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
    double scale,
  ) {
    // 只有彻底加载失败且无用户数据才显示错误
    if (currentUser == null && loadUsersAsync.hasError) {
      debugPrint('加载用户数据失败: ${loadUsersAsync.error}');
      return _paperArea(
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
          dateText: DateHelper.toChineseDate(selectedDate),
          date: selectedDate,
          onCalendarTap: () => _openCalendar(context, ref),
          onPreviousDay: _canChangeDay(selectedDate, -1)
              ? () => _changeDay(ref, selectedDate, -1)
              : null,
          onNextDay: _canChangeDay(selectedDate, 1)
              ? () => _changeDay(ref, selectedDate, 1)
              : null,
          scale: scale,
        ),
        if (currentUser != null && partner != null)
          _buildDayView(ref, currentUser, partner, context, scale)
        else
          Expanded(child: _paperArea()),
      ],
    );
  }

  /// 非日记内容状态也铺满同一张纸面，不额外覆盖已有的双联纸页。
  Widget _paperArea({Widget? child}) => ColoredBox(
    color: AppTheme.surfaceColor.withAlpha(235),
    child: SizedBox.expand(child: child),
  );

  /// 构建日视图
  Widget _buildDayView(
    WidgetRef ref,
    currentUser,
    partner,
    BuildContext context,
    double scale,
  ) {
    final dayMomentsAsync = ref.watch(dayMomentsProvider);

    return dayMomentsAsync.when(
      skipLoadingOnRefresh: true,
      data: (data) {
        final myMoment = data['myMoment'];
        final partnerMoment = data['partnerMoment'];
        return DaySplitView(
          onCreateMyMoment: () => _openCreateEditor(ref, context),
          onOpenReading: (moment) => _openReading(context, moment),
          myMoment: myMoment,
          partnerMoment: partnerMoment,
          myNickname: currentUser.nickname,
          partnerNickname: partner.nickname,
          myAvatarUrl: currentUser.avatarUrl,
          partnerAvatarUrl: partner.avatarUrl,
          scale: scale,
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
              ? (parent) =>
                    _openCommentDialog(context, ref, partnerMoment, parent)
              : null,
        );
      },
      loading: () => Expanded(child: _paperArea()),
      error: (e, _) {
        debugPrint('加载日记失败: $e');
        return Expanded(
          child: _paperArea(
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

  void _openReading(BuildContext context, Moment initialMoment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (readingContext) => Consumer(
          builder: (context, readingRef, _) {
            final day = readingRef.watch(dayMomentsProvider).value;
            var moment = initialMoment;
            if (day != null) {
              for (final entry in day.values) {
                if (entry?.id == initialMoment.id) moment = entry!;
              }
            }
            final currentUser = readingRef.watch(currentUserProvider);
            final partner = readingRef.watch(partnerUserProvider);
            final isSelf = moment.authorId == currentUser?.uid;
            final author = isSelf ? currentUser : partner;
            final other = isSelf ? partner : currentUser;
            final nickname = author?.nickname.trim();
            final displayName = nickname == null || nickname.isEmpty
                ? (isSelf ? '我' : 'TA')
                : nickname;
            final currentMoment = moment;
            return Scaffold(
              appBar: AppBar(title: Text('$displayName 的日记')),
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  key: PageStorageKey('reading-${currentMoment.id}'),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: MomentCard(
                        key: ValueKey(currentMoment.id),
                        moment: currentMoment,
                        nickname: displayName,
                        avatarUrl: author?.avatarUrl,
                        partnerNickname: other?.nickname ?? '',
                        isSelf: isSelf,
                        expandedReading: true,
                        onEdit: () => _openEditor(
                          readingContext,
                          readingRef,
                          DateHelper.parseDateStr(currentMoment.dateStr),
                          currentMoment,
                        ),
                        onComment: () => _openCommentDialog(
                          readingContext,
                          readingRef,
                          currentMoment,
                          null,
                        ),
                        onDeleteComment: (comment) => _deleteComment(
                          readingContext,
                          readingRef,
                          currentMoment,
                          comment,
                        ),
                        onReplyComment: (parent) => _openCommentDialog(
                          readingContext,
                          readingRef,
                          currentMoment,
                          parent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
        builder: (_) =>
            EditMomentScreen(date: date, existingMoment: existingMoment),
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

  String _commentDraftKey(String userId, Moment moment, Comment? replyTo) {
    return '${userId}_${moment.id}_${replyTo?.id ?? 'root'}';
  }

  /// 打开评论弹窗（新增 / 回复）
  Future<void> _openCommentDialog(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
    Comment? replyTo, // null = 新增顶级评论，非 null = 回复某条
  ) async {
    final currentUser = ref.read(currentUserProvider);
    final draftKey = _commentDraftKey(
      currentUser?.uid ?? 'anonymous',
      moment,
      replyTo,
    );
    final savedDraft = await DraftService.loadComment(draftKey);
    if (!context.mounted) return;

    final result = await showDialog<_CommentDialogResult>(
      context: context,
      builder: (ctx) => _DiaryCommentDialog(
        initialText: savedDraft ?? '',
        isReply: replyTo != null,
      ),
    );

    if (result == null || result.content.isEmpty) return;

    if (result.saveDraft) {
      try {
        await DraftService.saveComment(draftKey, result.content);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('评论草稿已保存')));
        }
      } catch (e) {
        debugPrint('评论草稿保存失败: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('评论草稿保存失败，请重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    {
      final newComment = Comment(
        id: _makeCommentId(),
        authorId: currentUser?.uid ?? '',
        content: result.content,
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
        await DraftService.clearComment(draftKey);
        // 立即更新本地缓存，确保刷新后读到最新数据
        await _updateCachedMomentComments(ref, moment.id, newComments);
        _refresh(ref);
      } catch (e) {
        debugPrint('发送评论失败: $e');
        // 上传失败自动保存为草稿，避免用户输入的内容丢失
        try {
          await DraftService.saveComment(draftKey, result.content);
        } catch (_) {}

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('评论失败，已自动为您保存为草稿，请重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 更新本地缓存中某条日记的评论
  Future<void> _updateCachedMomentComments(
    WidgetRef ref,
    String momentId,
    List<Comment> comments,
  ) async {
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
            child: Text(
              AppStrings.cancel,
              style: TextStyle(color: Colors.grey[600]),
            ),
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

    final newComments = moment.comments
        .where((c) => !toRemove.contains(c.id))
        .toList();

    final apiService = ref.read(apiServiceProvider);
    try {
      await apiService.updateMoment(moment.id, {
        'comments': newComments.map((c) => c.toJson()).toList(),
      });
      // 立即更新本地缓存
      await _updateCachedMomentComments(ref, moment.id, newComments);
      _refresh(ref);
    } catch (e) {
      debugPrint('删除评论失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除失败，请稍后重试'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
