import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/topic.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/topic_service.dart';
import '../utils/date_helper.dart';
import '../widgets/frosted_pill_button.dart';
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
  List<Topic>? _topics;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await _service.getTopics();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      debugPrint('加载话题列表失败: $e');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '网络连接异常，请检查网络后重试';
      });
    }
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
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty) return;

    try {
      await _service.createTopic(result, currentUser.uid);
      await _loadTopics();
    } catch (e) {
      debugPrint('创建话题失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('创建失败，请稍后重试'),
          backgroundColor: AppTheme.dangerColor,
        ),
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
            toolbarHeight: 44,
            actions: [
              IconButton(
                onPressed: _loading ? null : _loadTopics,
                tooltip: '刷新话题',
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: Padding(
            padding: EdgeInsets.only(
              bottom:
                  (MediaQuery.paddingOf(context).bottom -
                          MediaQuery.viewPaddingOf(context).bottom)
                      .clamp(0.0, double.infinity),
            ),
            child: FrostedPillButton(label: '创建话题', onTap: _createTopic),
          ),
          body: SafeArea(top: false, child: _buildBody(wallpaper.cardOpacity)),
        ),
      ],
    );
  }

  Widget _buildBody(double cardOpacity) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              '加载话题失败',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
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
            const Icon(
              Icons.forum_outlined,
              size: 48,
              color: AppTheme.selfColor,
            ),
            const SizedBox(height: 12),
            const Text(
              '聊聊今天以外的事',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '从一个话题开始，慢慢交换想法',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTopics,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
        itemCount: _topics!.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final topic = _topics![index];
          return Material(
            color: AppTheme.surfaceColor.withValues(alpha: cardOpacity),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TopicDetailScreen(topicId: topic.id),
                  ),
                );
                _loadTopics();
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.accentSurface,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 20,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            topic.title,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '由 ${_nickFor(topic.authorId)} 创建',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '更新于 ${DateHelper.toFriendlyDateTime(topic.latestUpdatedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
