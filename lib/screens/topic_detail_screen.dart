import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../models/topic.dart';
import '../providers/auth_provider.dart';
import '../services/topic_service.dart';
import '../utils/date_helper.dart';

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
  bool _isSending = false;

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

  String _nickFor(String authorId, String currentUid) {
    return authorId == currentUid ? '我' : authorId;
  }

  Future<void> _reply() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发帖'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写下你的想法...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('发送'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await _service.createPost(widget.topicId, currentUser.uid, result);
      await _loadTopic();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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

    return Scaffold(
      appBar: AppBar(title: Text(_topic?.title ?? '话题')),
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              child: Text(
                                                _nickFor(post.authorId, currentUid)[0],
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _nickFor(post.authorId, currentUid),
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
                                        Text(post.content,
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
                          color: Colors.white,
                          border: Border(top: BorderSide(color: Colors.grey[200]!)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _isSending ? null : _reply,
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
                            _isSending
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: Icon(Icons.send, color: AppTheme.primaryColor),
                                    onPressed: _reply,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return DateHelper.toShortTime(dt);
  }
}
