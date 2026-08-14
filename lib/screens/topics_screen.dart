import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/topic_service.dart';
import '../utils/date_helper.dart';
import '../widgets/wallpaper_layer.dart';
import 'topic_detail_screen.dart';

/// 话题列表页
class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key});

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen> {
  final _service = TopicService();
  List<dynamic>? _topics;
  bool _loading = true;
  String? _error;
  // 各话题最新更新时间（最近一条帖子时间，无帖子则为话题创建时间）
  final Map<String, DateTime> _latestUpdate = {};

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await _service.getTopics();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
      // 列表文字先秒开，最新更新时间后台并行补齐（每次打开都会重新比对）
      _loadLatestUpdates(topics);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 并行拉取每个话题的详情，计算最新更新时间
  /// （列表接口只返回创建时间，最新帖子时间需从详情里取）
  Future<void> _loadLatestUpdates(List<dynamic> topics) async {
    final results = await Future.wait(topics.map((t) async {
      try {
        final detail = await _service.getTopic(t.id);
        DateTime latest = t.createdAt;
        for (final p in detail.posts) {
          if (p.createdAt.isAfter(latest)) latest = p.createdAt;
        }
        return MapEntry<String, DateTime>(t.id, latest);
      } catch (_) {
        return MapEntry<String, DateTime>(t.id, t.createdAt);
      }
    }));
    if (!mounted) return;
    setState(() {
      for (final e in results) {
        _latestUpdate[e.key] = e.value;
      }
    });
  }

  Future<void> _createTopic() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建话题'),
        content: SelectionContainer.disabled(
          child: TextField(
            controller: controller,
            autofocus: true,
            contextMenuBuilder: (context, editableTextState) =>
                AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: editableTextState.contextMenuButtonItems,
            ),
            decoration: const InputDecoration(hintText: '输入话题标题'),
          ),
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
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      await _service.createTopic(result, currentUser.uid);
      await _loadTopics();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _nickFor(String authorId) {
    final currentUser = ref.read(currentUserProvider);
    final partner = ref.read(partnerUserProvider);
    if (authorId == currentUser?.uid) return currentUser?.nickname ?? authorId;
    if (authorId == partner?.uid) return partner?.nickname ?? authorId;
    return authorId;
  }

  @override
  Widget build(BuildContext context) {
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
            title: const Text('话题'),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _createTopic,
            child: const Icon(Icons.add),
          ),
          body: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('后端不可用', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _loadTopics, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_topics == null || _topics!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无话题', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 4),
            Text('点击右下角 + 新建', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTopics,
      child: ListView.separated(
        itemCount: _topics!.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final topic = _topics![index];
          return ListTile(
            isThreeLine: true,
            title: SelectableText(topic.title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '由 ${_nickFor(topic.authorId)} 创建',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  _latestUpdate[topic.id] != null
                      ? '最新更新：${DateHelper.toFriendlyDateTime(_latestUpdate[topic.id]!)}'
                      : '最新更新：加载中…',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TopicDetailScreen(topicId: topic.id)),
              );
              _loadTopics();
            },
          );
        },
      ),
    );
  }
}
