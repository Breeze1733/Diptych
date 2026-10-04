import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/draft_service.dart';
import '../services/topic_service.dart';
import '../utils/foreground_service_helper.dart';
import '../utils/wakelock_helper.dart';

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
  String? _loadedDraft;
  bool _isExitDialogShowing = false;
  bool _hasPublishedSuccessfully = false;

  bool get _hasChanges {
    if (_hasPublishedSuccessfully) return false;
    final current = _contentController.text.trim();
    if (_loadedDraft != null) {
      return current != _loadedDraft;
    }
    return current.isNotEmpty;
  }

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
    _loadedDraft = content.trim();
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
      _loadedDraft = content;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存')),
      );
    } catch (e) {
      debugPrint('保存草稿失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存草稿失败，请重试'), backgroundColor: Colors.red),
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
    await WakelockHelper.acquire(timeout: const Duration(minutes: 5));
    await ForegroundServiceHelper.start(
      title: 'Diptych 话题发帖',
      content: '正在发布帖子内容...',
      maxProgress: 1,
      progress: 0,
    );

    try {
      await _service.createPost(widget.topicId, currentUser.uid, content);
      await DraftService.clearTopicPost(_draftKey);
      _hasPublishedSuccessfully = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发布成功'), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('发布帖子失败: $e');
      // 发布失败时自动保存草稿，确保用户输入的内容不丢失
      try {
        await DraftService.saveTopicPost(_draftKey, content);
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('发布失败，已自动为您保存为草稿，请重试'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      await ForegroundServiceHelper.stop();
      await WakelockHelper.release();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleBackPress() async {
    if (_isSaving || _isSavingDraft) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    if (_isExitDialogShowing || !mounted) return;
    _isExitDialogShowing = true;
    try {
      final shouldPop = await _showExitConfirmDialog();
      if (shouldPop && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      _isExitDialogShowing = false;
    }
  }

  Future<bool> _showExitConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出发帖'),
        content: const Text('当前内容尚未发布，是否保留草稿？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('放弃'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '保留草稿',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (result == null) {
      return false;
    }

    if (result == true) {
      final content = _contentController.text.trim();
      if (content.isNotEmpty) {
        try {
          await DraftService.saveTopicPost(_draftKey, content);
          _loadedDraft = content;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('草稿已保存'),
                backgroundColor: AppTheme.primaryColor,
              ),
            );
          }
        } catch (_) {}
      }
      return true;
    } else {
      await DraftService.clearTopicPost(_draftKey);
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: _handleBackPress,
          ),
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
      ),
    );
  }
}
