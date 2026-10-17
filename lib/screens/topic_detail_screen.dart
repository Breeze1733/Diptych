import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/topic.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/topic_service.dart';
import '../utils/date_helper.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/wallpaper_layer.dart';
import 'topic_post_screen.dart';

/// 话题讨论页（论坛风格）
class TopicDetailScreen extends ConsumerStatefulWidget {
  final String topicId;

  const TopicDetailScreen({super.key, required this.topicId});

  @override
  ConsumerState<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends ConsumerState<TopicDetailScreen> {
  final _service = TopicService();
  Topic? _topic;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTopic();
  }

  Future<void> _loadTopic() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topic = await _service.getTopic(widget.topicId);
      if (!mounted) return;
      setState(() {
        _topic = topic;
        _loading = false;
      });
    } catch (e) {
      debugPrint('加载话题详情失败: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络连接异常，请检查网络后重试';
      });
    }
  }

  String _nickFor(String authorId) {
    final currentUser = ref.read(currentUserProvider);
    final partner = ref.read(partnerUserProvider);
    if (authorId == currentUser?.uid) return currentUser?.nickname ?? authorId;
    if (authorId == partner?.uid) return partner?.nickname ?? authorId;
    return authorId;
  }

  /// 从缓存的用户信息里取头像 URL（缓存优先，见 loadUsersProvider）
  String _avatarFor(String authorId) {
    final currentUser = ref.read(currentUserProvider);
    final partner = ref.read(partnerUserProvider);
    if (authorId == currentUser?.uid) return currentUser?.avatarUrl ?? '';
    if (authorId == partner?.uid) return partner?.avatarUrl ?? '';
    return '';
  }

  Future<void> _openPostEditor() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TopicPostScreen(
          topicId: widget.topicId,
          topicTitle: _topic?.title ?? '话题',
        ),
      ),
    );
    if (result == true) await _loadTopic();
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定删除这条帖子？'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deletePost(widget.topicId, post.id);
      await _loadTopic();
    } catch (e) {
      debugPrint('删除帖子失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('删除失败，请稍后重试'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final wallpaper = ref.watch(wallpaperSettingsProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(
          url: wallpaper.topicUrl,
          opacity: wallpaper.topicOpacity,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            title: Text(
              _topic?.title ?? '话题',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: _buildBody(currentUid, wallpaper.cardOpacity),
        ),
      ],
    );
  }

  Widget _buildBody(String currentUid, double cardOpacity) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                '暂时无法加载讨论',
                style: TextStyle(fontSize: 17, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _loadTopic, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: _topic!.posts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 44,
                        color: AppTheme.selfColor,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '还没有人开口',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '写下第一个想法，开始这段对话',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTopic,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _topic!.posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _buildPostCard(
                      _topic!.posts[index],
                      currentUid,
                      cardOpacity,
                    ),
                  ),
                ),
        ),
        _buildReplyBar(cardOpacity),
      ],
    );
  }

  Widget _buildPostCard(Post post, String currentUid, double cardOpacity) {
    final isMe = post.authorId == currentUid;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppTheme.surfaceColor.withValues(alpha: cardOpacity),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // URL 不变时复用头像，避免文字更新触发图片闪烁。
                KeyedSubtree(
                  key: ValueKey(
                    'avatar_${post.authorId}_${_avatarFor(post.authorId)}',
                  ),
                  child: AvatarWidget(
                    avatarUrl: _avatarFor(post.authorId),
                    size: 36,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        _nickFor(post.authorId),
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isMe
                              ? AppTheme.selfColor
                              : AppTheme.partnerColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatTime(post.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMe)
                  IconButton(
                    onPressed: () => _deletePost(post),
                    tooltip: '删除这条回复',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              post.content,
              style: const TextStyle(
                fontSize: 15,
                height: 1.7,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar(double cardOpacity) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: cardOpacity),
        border: const Border(top: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '还有什么想和对方聊聊？',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openPostEditor,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('写回复'),
                style: FilledButton.styleFrom(minimumSize: const Size(112, 46)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 评论时间：显示真实时间（不再用"X小时前"相对时间）
  String _formatTime(DateTime dt) => DateHelper.toFriendlyDateTime(dt);
}
