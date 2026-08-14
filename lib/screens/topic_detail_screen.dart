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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
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
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUid = currentUser?.uid ?? '';
    final wallpaper = ref.watch(wallpaperSettingsProvider);

    // 壁纸垫在整个 Scaffold 后面，Scaffold 保持正常布局，杜绝重叠/空档
    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(url: wallpaper.topicUrl, opacity: wallpaper.topicOpacity),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(_topic?.title ?? '话题'),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('后端不可用', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _loadTopic, child: const Text('重试')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _topic!.posts.isEmpty
                          ? Center(
                              child: Text('暂无讨论，快来发言吧',
                                  style: TextStyle(color: Colors.grey[400])),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _topic!.posts.length,
                              itemBuilder: (context, index) {
                                final post = _topic!.posts[index];
                                final isMe = post.authorId == currentUid;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  // 半透明白卡片：让话题壁纸能透过显示
                                  color: const Color(0xD9FFFFFF),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // 头像：从缓存加载（CachedNetworkImage）。
                                            // key 绑定头像 URL —— URL 不变时元素被复用，
                                            // 文字刷新不会触发图片重新加载/闪烁；
                                            // 仅当头像 URL 变化时才会重新拉取图片。
                                            KeyedSubtree(
                                              key: ValueKey(
                                                  'avatar_${post.authorId}_${_avatarFor(post.authorId)}'),
                                              child: AvatarWidget(
                                                avatarUrl: _avatarFor(post.authorId),
                                                nickname: _nickFor(post.authorId),
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SelectableText(
                                              _nickFor(post.authorId),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isMe
                                                    ? AppTheme.primaryColor
                                                    : Colors.grey[700],
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatTime(post.createdAt),
                                              style: TextStyle(
                                                  fontSize: 11, color: Colors.grey[400]),
                                            ),
                                            if (isMe)
                                              GestureDetector(
                                                onTap: () => _deletePost(post),
                                                child: Padding(
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: Icon(Icons.close,
                                                      size: 16, color: Colors.grey[400]),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(post.content,
                                            style:
                                                const TextStyle(fontSize: 14, height: 1.5)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // 底部输入栏
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xD9FFFFFF),
                          border: Border(top: BorderSide(color: Colors.grey[200]!)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _openPostEditor,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '写下你的想法...',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.send, color: AppTheme.primaryColor),
                              onPressed: _openPostEditor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // 评论时间：显示真实时间（不再用"X小时前"相对时间）
  String _formatTime(DateTime dt) => DateHelper.toFriendlyDateTime(dt);
}
