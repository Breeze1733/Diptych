import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../utils/date_helper.dart';
import 'avatar_widget.dart';
import 'image_gallery.dart';

/// 朋友圈风格动态卡片
/// 展示：头像 + 昵称 + 心情分 + 封面图（点击展开图片列表）+ 感受文字 + 时间 + 编辑/评论按钮 + 评论列表
class MomentCard extends StatelessWidget {
  final Moment moment;
  final String nickname;
  final String? avatarUrl;
  final String partnerNickname;
  final bool isSelf; // 是否是自己（决定显示"编辑"还是"评论"）
  final VoidCallback? onEdit;
  final VoidCallback? onComment;
  final void Function(Comment comment)? onDeleteComment;
  final void Function(Comment? parentComment)? onReplyComment;

  const MomentCard({
    super.key,
    required this.moment,
    this.nickname = '',
    this.avatarUrl,
    this.partnerNickname = '',
    this.isSelf = true,
    this.onEdit,
    this.onComment,
    this.onDeleteComment,
    this.onReplyComment,
  });

  /// 根据 authorId 获取显示昵称
  String _nickFor(String authorId) {
    return authorId == moment.authorId ? nickname : partnerNickname;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.cardColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像 + 昵称 + 心情分
          Row(
            children: [
              AvatarWidget(
                avatarUrl: avatarUrl,
                nickname: nickname,
                size: 32,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(nickname, style: AppTheme.momentNickname),
              ),
              // 心情分数
              if (moment.mood != null) _buildMoodBadge(),
            ],
          ),
          const SizedBox(height: 10),

          // 封面图（第一张），点击展开全部图片
          _buildCoverBox(context),
          const SizedBox(height: 10),

          // 感受文字
          if (moment.feeling.isNotEmpty)
            Text(moment.feeling, style: AppTheme.momentContent),

          const SizedBox(height: 8),

          // 最新编辑时间 + 操作按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  DateHelper.toEditTime(moment.updatedAt),
                  style: AppTheme.momentTime,
                ),
              ),
              // 编辑按钮（自己）或评论按钮（对方）
              _buildActionButton(),
            ],
          ),

          // 评论列表（朋友圈风格）
          if (moment.comments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildComments(context),
          ],
        ],
      ),
    );
  }

  /// 心情分数徽章
  Widget _buildMoodBadge() {
    final mood = moment.mood!;
    Color moodColor;
    if (mood >= 8) {
      moodColor = const Color(0xFF07C160); // 开心绿
    } else if (mood >= 5) {
      moodColor = const Color(0xFFFFA726); // 一般橙
    } else {
      moodColor = const Color(0xFF78909C); // 低落灰蓝
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: moodColor.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: moodColor.withAlpha(80), width: 0.5),
      ),
      child: Text(
        '$mood 分',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: moodColor,
        ),
      ),
    );
  }

  /// 编辑 / 评论按钮
  Widget _buildActionButton() {
    if (isSelf) {
      return GestureDetector(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withAlpha(15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF2196F3).withAlpha(60), width: 0.5),
          ),
          child: const Text(
            AppStrings.editButton,
            style: TextStyle(fontSize: 11, color: Color(0xFF2196F3), fontWeight: FontWeight.w500),
          ),
        ),
      );
    } else {
      return GestureDetector(
        onTap: onComment,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.primaryColor.withAlpha(60), width: 0.5),
          ),
          child: const Text(
            AppStrings.commentButton,
            style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }
  }

  /// 评论区：每个一级评论 + 其回复为一个灰色块，块之间白底分隔
  Widget _buildComments(BuildContext context) {
    final replies = <String, List<Comment>>{};
    for (final c in moment.comments) {
      if (c.replyTo != null) {
        replies.putIfAbsent(c.replyTo!, () => []).add(c);
      }
    }

    final topLevel = moment.comments.where((c) => c.replyTo == null).toList();
    if (topLevel.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < topLevel.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: _buildCommentTree(context, topLevel[i], replies),
          ),
        ],
      ],
    );
  }

  /// 递归渲染评论树：当前评论 + 所有子回复
  Widget _buildCommentTree(BuildContext context, Comment comment, Map<String, List<Comment>> replies) {
    final children = replies[comment.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showCommentActions(context, comment),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${_nickFor(comment.authorId)}：',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                      height: 1.4,
                    ),
                  ),
                  TextSpan(
                    text: comment.content,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (children != null && children.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                _buildCommentTree(context, child, replies),
            ],
          ),
      ],
    );
  }

  /// 点击评论弹出操作菜单
  void _showCommentActions(BuildContext context, Comment comment) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            // 回复
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('回复'),
              onTap: () {
                Navigator.pop(ctx);
                // 传入被回复的评论
                onReplyComment?.call(comment);
              },
            ),
            // 删除
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                onDeleteComment?.call(comment);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 封面图：第一张图片，右下角显示总张数，点击弹出图片列表
  Widget _buildCoverBox(BuildContext context) {
    final urls = moment.imageUrls;

    final content = urls.isNotEmpty
        ? GestureDetector(
            onTap: () => showImageGallery(context, urls),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: urls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => _placeholder(''),
                  errorWidget: (_, _, _) => _placeholder(''),
                ),
                // 张数角标
                if (urls.length > 1)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            '${urls.length}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        : _placeholder('');

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _placeholder(String label) {
    return Container(
      color: Colors.grey[100],
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 28, color: Colors.grey[300]),
          if (label.isNotEmpty)
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ),
    );
  }
}
