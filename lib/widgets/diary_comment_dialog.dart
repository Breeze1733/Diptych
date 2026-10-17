import 'dart:math';

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/moment.dart';
import '../services/draft_service.dart';

/// 发布成功由调用方确认：服务端读回、详情更新并完成布局后才关闭。
class DiaryCommentDialog extends StatefulWidget {
  final String authorId;
  final String draftKey;
  final String initialText;
  final Comment? pendingComment;
  final Comment? replyTo;
  final Future<void> Function(Comment) onPublish;

  const DiaryCommentDialog({
    super.key,
    required this.authorId,
    required this.draftKey,
    required this.initialText,
    required this.onPublish,
    this.pendingComment,
    this.replyTo,
  });

  @override
  State<DiaryCommentDialog> createState() => _DiaryCommentDialogState();
}

class _DiaryCommentDialogState extends State<DiaryCommentDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  late Comment? _pending = widget.pendingComment;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (_submitting) return;
    try {
      await DraftService.saveComment(widget.draftKey, _controller.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '草稿保存失败，文字仍保留在这里，请重试');
    }
  }

  Future<void> _publish() async {
    if (_submitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '先写下想说的话吧');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final pending = _pending;
      final comment = pending != null && pending.content == text
          ? pending
          : Comment(
              id: 'c_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}',
              authorId: widget.authorId,
              content: text,
              replyTo: widget.replyTo?.id,
              createdAt: DateTime.now(),
            );
      _pending = comment;
      await DraftService.saveComment(widget.draftKey, text);
      await DraftService.savePendingComment(widget.draftKey, comment);
      await widget.onPublish(comment);
      // 清理草稿失败不能把已经确认的评论误报成发送失败。
      try {
        await DraftService.clearComment(widget.draftKey);
      } catch (e) {
        debugPrint('清理评论草稿失败: $e');
      }
      if (mounted) Navigator.pop(context, comment.id);
    } catch (e) {
      debugPrint('评论发布或确认失败: $e');
      if (mounted) {
        setState(() => _error = '尚未确认发送成功，文字已保留。请重试确认，不会重复发布。');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop && result == null && !_submitting) {
        DraftService.saveComment(
          widget.draftKey,
          _controller.text.trim(),
        ).catchError((Object e) => debugPrint('保存评论草稿失败: $e'));
      }
    },
    child: AlertDialog(
      title: Text(widget.replyTo == null ? '写留言' : '回复留言'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: '写下想说的话…'),
            ),
            if (_submitting) ...[
              const SizedBox(height: 16),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '正在发布并确认留言…',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.dangerColor,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _saveDraft,
          child: const Text('存草稿并返回'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _publish,
          child: Text(_error == null ? '发布' : '重试确认'),
        ),
      ],
    ),
  );
}
