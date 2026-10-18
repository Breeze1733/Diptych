import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../services/cache_service.dart';
import '../services/draft_service.dart';
import '../utils/date_helper.dart';
import '../widgets/diary_comment_dialog.dart';
import '../widgets/moment_card.dart';
import 'edit_moment_screen.dart';

/// 详情持有已确认的日记与滚动控制器，避免旧的列表缓存覆盖阅读中的内容。
class DiaryReadingScreen extends ConsumerStatefulWidget {
  final Moment initialMoment;

  const DiaryReadingScreen({super.key, required this.initialMoment});

  @override
  ConsumerState<DiaryReadingScreen> createState() => _DiaryReadingScreenState();
}

class _DiaryReadingScreenState extends ConsumerState<DiaryReadingScreen> {
  late Moment _moment = widget.initialMoment;
  final _scrollController = ScrollController();
  bool _refreshing = false;
  bool _publishing = false;
  bool _editing = false;
  bool _commentDialogOpen = false;
  int _loadVersion = 0;
  String? _focusCommentId;
  Completer<void>? _commentRevealed;

  bool get _canEdit =>
      _moment.id.isNotEmpty &&
      !_refreshing &&
      !_publishing &&
      !_editing &&
      !_commentDialogOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _acceptMoment(Moment moment, {String? focusCommentId}) async {
    if (!mounted) return;
    setState(() {
      _moment = moment;
      _focusCommentId = focusCommentId;
    });
    try {
      await CacheService.saveMoment(moment);
    } catch (e) {
      debugPrint('详情已更新，写入日记缓存失败: $e');
    }
    if (mounted) ref.invalidate(dayMomentsProvider);
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_refreshing || _publishing || _editing) return;
    final version = ++_loadVersion;
    setState(() => _refreshing = true);
    try {
      final api = ref.read(apiServiceProvider);
      final moment = _moment.id.isEmpty
          ? await api.getMomentByDate(_moment.authorId, _moment.dateStr)
          : await api.getMoment(_moment.id);
      if (moment == null) throw Exception('日记已不存在');
      if (!mounted || version != _loadVersion) return;
      await _acceptMoment(moment);
    } catch (e) {
      debugPrint('刷新日记失败: $e');
      if (mounted && !quiet && version == _loadVersion) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('刷新失败，已保留当前内容，请稍后重试')));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _publishComment(Comment comment) async {
    if (_editing || _publishing) throw StateError('日记正在更新，请稍后重试');
    final api = ref.read(apiServiceProvider);
    ++_loadVersion; // 正在途中的刷新结果从此失效。
    setState(() {
      _publishing = true;
      _refreshing = false;
    });
    try {
      final saved = await api.addComment(_moment.id, comment);
      bool contains(Moment moment) => moment.comments.any(
        (item) =>
            item.id == comment.id &&
            item.authorId == comment.authorId &&
            item.content == comment.content &&
            item.replyTo == comment.replyTo,
      );
      if (!contains(saved)) throw Exception('服务器没有返回已保存的评论');
      Moment? confirmed;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: attempt * 450));
        }
        try {
          final fresh = await api
              .getMoment(_moment.id)
              .timeout(const Duration(seconds: 8));
          if (contains(fresh)) {
            confirmed = fresh;
            break;
          }
        } catch (_) {
          if (attempt == 2) rethrow;
        }
      }
      if (confirmed == null) throw Exception('尚未从服务器读回新评论');
      if (!mounted) throw Exception('日记页面已关闭');
      final revealed = Completer<void>();
      _commentRevealed = revealed;
      await _acceptMoment(confirmed, focusCommentId: comment.id);
      // 等待布局和必要的滚动完成，确认留言已进入可见区域再关闭弹窗。
      await revealed.future.timeout(const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _openCommentDialog([Comment? replyTo]) async {
    final user = ref.read(currentUserProvider);
    if (user == null ||
        _editing ||
        _publishing ||
        _commentDialogOpen ||
        _moment.id.isEmpty) {
      return;
    }
    setState(() => _commentDialogOpen = true);
    final key = '${user.uid}_${_moment.id}_${replyTo?.id ?? 'root'}';
    try {
      final text = await DraftService.loadComment(key);
      final pending = await DraftService.loadPendingComment(key);
      if (!mounted) return;
      await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DiaryCommentDialog(
          authorId: user.uid,
          draftKey: key,
          initialText: text ?? '',
          pendingComment: pending,
          replyTo: replyTo,
          onPublish: _publishComment,
        ),
      );
    } finally {
      if (mounted) setState(() => _commentDialogOpen = false);
    }
  }

  Future<void> _edit() async {
    // 刷新与缓存写入结束后才能编辑，避免编辑器拿到过期快照。
    if (!_canEdit) return;
    ++_loadVersion;
    setState(() => _editing = true);
    bool? saved;
    try {
      saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EditMomentScreen(
            date: DateHelper.parseDateStr(_moment.dateStr),
            existingMoment: _moment,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _deleteComment(Comment comment) async {
    if (_editing || _publishing || _commentDialogOpen) return;
    setState(() => _commentDialogOpen = true);
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除留言'),
          content: const Text('删除这条留言及其下的所有回复？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _commentDialogOpen = false);
    }
    if (confirmed != true || !mounted) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    ++_loadVersion;
    setState(() {
      _publishing = true;
      _refreshing = false;
    });
    try {
      final moment = await ref
          .read(apiServiceProvider)
          .deleteComment(_moment.id, comment.id, user.uid);
      if (mounted) await _acceptMoment(moment);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final isSelf = _moment.authorId == user?.uid;
    final author = isSelf ? user : partner;
    final other = isSelf ? partner : user;
    final nickname = author?.nickname.trim() ?? '';
    final name = nickname.isEmpty ? (isSelf ? '我' : 'TA') : nickname;
    return Scaffold(
      appBar: AppBar(
        title: Text('$name 的日记'),
        actions: [
          IconButton(
            tooltip: '刷新这条日记',
            onPressed: _refreshing || _publishing || _editing
                ? null
                : () => _refresh(),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: PageStorageKey('reading-${_moment.id}'),
          controller: _scrollController,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: MomentCard(
                key: ValueKey(_moment.id),
                moment: _moment,
                nickname: name,
                avatarUrl: author?.avatarUrl,
                partnerNickname: other?.nickname ?? '',
                isSelf: isSelf,
                expandedReading: true,
                focusCommentId: _focusCommentId,
                showInlineAction: isSelf,
                onCommentRevealed: (_) {
                  final pending = _commentRevealed;
                  if (pending != null && !pending.isCompleted) {
                    pending.complete();
                  }
                },
                onEdit: isSelf && _canEdit ? _edit : null,
                onComment: _openCommentDialog,
                onDeleteComment: _deleteComment,
                onReplyComment: _openCommentDialog,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: OutlinedButton.icon(
            onPressed: _editing || _publishing || _moment.id.isEmpty
                ? null
                : _openCommentDialog,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('写留言'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
