import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/draft_service.dart';
import '../services/topic_service.dart';

/// 话题发帖页：独立页面，仅编辑文字内容。
class TopicPostScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String topicTitle;

  const TopicPostScreen({
    super.key,
    required this.topicId,
    required this.topicTitle,
  });

  @override
  ConsumerState<TopicPostScreen> createState() => _TopicPostScreenState();
}

class _TopicPostScreenState extends ConsumerState<TopicPostScreen> {
  final _contentController = TextEditingController();
  final _service = TopicService();
  bool _isSaving = false;
  bool _isSavingDraft = false;

  String get _draftKey {
    final userId = ref.read(currentUserProvider)?.uid ?? 'anonymous';
    return '${userId}_${widget.topicId}';
  }

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final content = await DraftService.loadTopicPost(_draftKey);
    if (!mounted || content == null) return;
    _contentController.text = content;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveDraft() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入帖子内容后再保存草稿')),
      );
      return;
    }

    setState(() => _isSavingDraft = true);
    try {
      await DraftService.saveTopicPost(_draftKey, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存草稿失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _handlePublish() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入帖子内容')),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() => _isSaving = true);
    try {
      await _service.createPost(widget.topicId, currentUser.uid, content);
      await DraftService.clearTopicPost(_draftKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发布成功'), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖'),
        actions: [
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: _isSavingDraft || _isSaving ? null : _handleSaveDraft,
              child: _isSavingDraft
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('存草稿'),
            ),
          ),
          SizedBox(
            width: 56,
            child: TextButton(
              onPressed: _isSaving || _isSavingDraft ? null : _handlePublish,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '发布',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.topicTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            const Text(
              '帖子内容',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SelectionContainer.disabled(
              child: TextField(
                controller: _contentController,
                autofocus: true,
                minLines: 8,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: editableTextState.contextMenuButtonItems,
                ),
                decoration: const InputDecoration(hintText: '写下你的想法...'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
