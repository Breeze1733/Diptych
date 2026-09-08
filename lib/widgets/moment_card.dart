import "../utils/motion_photo_helper.dart";
import "package:flutter/material.dart";

import "package:cached_network_image/cached_network_image.dart";
import "../constants/app_theme.dart";
import "../constants/strings.dart";
import "../models/moment.dart";
import "../utils/date_helper.dart";
import "avatar_widget.dart";
import "image_gallery.dart";

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
  final double scale;

  const MomentCard({
    super.key,
    required this.moment,
    this.nickname = "",
    this.avatarUrl,
    this.partnerNickname = "",
    this.isSelf = true,
    this.onEdit,
    this.onComment,
    this.onDeleteComment,
    this.onReplyComment,
    this.scale = 1.0,
  });

  /// 根据 authorId 获取显示昵称
  String _nickFor(String authorId) {
    return authorId == moment.authorId ? nickname : partnerNickname;
  }

  @override
  Widget build(BuildContext context) {
    final double cardPadding = (12 * scale).clamp(6.0, 12.0);
    final double avatarSize = (32 * scale).clamp(22.0, 32.0);
    final double gapH = (8 * scale).clamp(4.0, 8.0);
    final double gapV = (10 * scale).clamp(4.0, 10.0);

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: const BoxDecoration(
        // 半透明白卡片：让壁纸能透过卡片显示（85% 不透明白）
        color: Color(0xD9FFFFFF),
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
              AvatarWidget(avatarUrl: avatarUrl, size: avatarSize),
              SizedBox(width: gapH),
              Expanded(
                child: SelectableText(
                  nickname,
                  style: AppTheme.momentNickname.copyWith(
                    fontSize: (15 * scale).clamp(11.0, 15.0),
                  ),
                ),
              ),
              // 心情分数
              if (moment.mood != null) _buildMoodBadge(),
            ],
          ),
          SizedBox(height: gapV),

          // 封面图（第一张），点击展开全部图片
          _buildCoverBox(context),
          SizedBox(height: gapV),

          // 感受文字（可长按复制）
          if (moment.feeling.isNotEmpty)
            SelectableText(
              moment.feeling,
              style: AppTheme.momentContent.copyWith(
                fontSize: (15 * scale).clamp(11.0, 15.0),
              ),
            ),

          SizedBox(height: (8 * scale).clamp(4.0, 8.0)),

          // 最新编辑时间 + 操作按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  DateHelper.toEditTime(moment.updatedAt),
                  style: AppTheme.momentTime.copyWith(
                    fontSize: (12 * scale).clamp(9.0, 12.0),
                  ),
                ),
              ),
              // 编辑按钮（自己）或评论按钮（对方）
              _buildActionButton(),
            ],
          ),

          // 评论列表（朋友圈风格）
          if (moment.comments.isNotEmpty) ...[
            SizedBox(height: (8 * scale).clamp(4.0, 8.0)),
            _buildComments(context),
          ],
        ],
      ),
    );
  }

  /// 心情分数徽章
  Widget _buildMoodBadge() {
    final mood = moment.mood!;
    final moodColor = AppTheme.moodColor(mood);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (8 * scale).clamp(4.0, 8.0),
        vertical: (2 * scale).clamp(1.0, 2.0),
      ),
      decoration: BoxDecoration(
        color: moodColor.withAlpha(20),
        borderRadius: BorderRadius.circular((10 * scale).clamp(6.0, 10.0)),
        border: Border.all(color: moodColor.withAlpha(80), width: 0.5),
      ),
      child: Text(
        "$mood 分",
        style: TextStyle(
          fontSize: (12 * scale).clamp(9.0, 12.0),
          fontWeight: FontWeight.w600,
          color: moodColor,
        ),
      ),
    );
  }

  /// 编辑 / 评论按钮
  Widget _buildActionButton() {
    final double btnPadH = (8 * scale).clamp(4.0, 8.0);
    final double btnPadV = (3 * scale).clamp(2.0, 3.0);
    final double btnFontSize = (11 * scale).clamp(9.0, 11.0);

    if (isSelf) {
      return GestureDetector(
        onTap: onEdit,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: btnPadV),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withAlpha(15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF2196F3).withAlpha(60),
              width: 0.5,
            ),
          ),
          child: Text(
            AppStrings.editButton,
            style: TextStyle(
              fontSize: btnFontSize,
              color: const Color(0xFF2196F3),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else {
      return GestureDetector(
        onTap: onComment,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: btnPadV),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppTheme.primaryColor.withAlpha(60),
              width: 0.5,
            ),
          ),
          child: Text(
            AppStrings.commentButton,
            style: TextStyle(
              fontSize: btnFontSize,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
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
          if (i > 0) SizedBox(height: (4 * scale).clamp(2.0, 4.0)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all((8 * scale).clamp(4.0, 8.0)),
            decoration: BoxDecoration(
              // 半透明评论气泡：让壁纸透出
              color: const Color(0xE6FFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _buildCommentTree(context, topLevel[i], replies),
          ),
        ],
      ],
    );
  }

  /// 递归渲染评论树：当前评论 + 所有子回复
  Widget _buildCommentTree(
    BuildContext context,
    Comment comment,
    Map<String, List<Comment>> replies,
  ) {
    final children = replies[comment.id];
    final double commentFontSize = (13 * scale).clamp(10.0, 13.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 短按弹操作菜单、长按框选复制，用 SelectableText 自带的 onTap，
        // 与外层 GestureDetector 叠放会让 tap 被选择手势抢走（竞技场冲突）
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "${_nickFor(comment.authorId)}：",
                  style: TextStyle(
                    fontSize: commentFontSize,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: comment.content,
                  style: TextStyle(
                    fontSize: commentFontSize,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            onTap: () => _showCommentActions(context, comment),
          ),
        ),

        // 子回复列表（递归）
        if (children != null)
          for (final child in children)
            _buildCommentTree(context, child, replies),
      ],
    );
  }

  /// 弹出评论操作底栏（回复 / 删除）
  void _showCommentActions(BuildContext context, Comment comment) {
    final isMyComment = comment.authorId == moment.authorId ? isSelf : !isSelf;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 提示当前操作的评论内容摘要
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  "评论：${comment.content}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ),
              const Divider(height: 1),
              // 回复
              ListTile(
                leading: const Icon(Icons.reply, size: 20),
                title: const Text("回复", style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  onReplyComment?.call(comment);
                },
              ),
              // 仅自己发布的评论可以删除
              if (isMyComment) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  title: const Text("删除", style: TextStyle(fontSize: 15, color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onDeleteComment?.call(comment);
                  },
                ),
              ],
            ],
          ),
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
                  placeholder: (_, _) => _placeholder(""),
                  errorWidget: (_, _, _) => _placeholder(""),
                ),
                // 实况角标
                _MomentCoverLiveBadge(url: urls.first),
                // 张数角标
                if (urls.length > 1)
                  Positioned(
                    right: (6 * scale).clamp(4.0, 6.0),
                    bottom: (6 * scale).clamp(4.0, 6.0),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: (6 * scale).clamp(4.0, 6.0),
                        vertical: (2 * scale).clamp(1.0, 2.0),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: (12 * scale).clamp(10.0, 12.0),
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            "${urls.length}",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (11 * scale).clamp(9.0, 11.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        : _placeholder("");

    final double coverHeight = (140 * scale).clamp(70.0, 140.0);

    return Container(
      height: coverHeight,
      decoration: BoxDecoration(
        // 半透明白封面底：让壁纸透出
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular((6 * scale).clamp(4.0, 6.0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _placeholder(String label) {
    return Container(
      color: const Color(0xE6FFFFFF),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: (28 * scale).clamp(18.0, 28.0), color: Colors.grey[300]),
          if (label.isNotEmpty)
            Text(
              label,
              style: TextStyle(fontSize: (10 * scale).clamp(8.0, 10.0), color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }
}

/// 动态卡片封面图上的实况角标
class _MomentCoverLiveBadge extends StatefulWidget {
  final String url;
  const _MomentCoverLiveBadge({required this.url});

  @override
  State<_MomentCoverLiveBadge> createState() => _MomentCoverLiveBadgeState();
}

class _MomentCoverLiveBadgeState extends State<_MomentCoverLiveBadge> {
  bool _isMotion = false;

  @override
  void initState() {
    super.initState();
    _checkMotion();
  }

  @override
  void didUpdateWidget(_MomentCoverLiveBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _checkMotion();
    }
  }

  Future<void> _checkMotion() async {
    final isMotion = await MotionPhotoHelper.isMotionPhotoUrl(widget.url);
    if (mounted && isMotion) {
      setState(() => _isMotion = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMotion) return const SizedBox.shrink();

    return Positioned(
      left: 6,
      bottom: 6,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(160),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white38, width: 0.8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.motion_photos_on, size: 11, color: Colors.white),
              SizedBox(width: 3),
              Text(
                "实况",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
