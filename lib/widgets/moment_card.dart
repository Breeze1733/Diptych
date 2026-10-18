import '../utils/motion_photo_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../services/private_image_cache.dart';
import '../utils/date_helper.dart';
import 'avatar_widget.dart';
import 'image_gallery.dart';

/// 双联纸页中的一天；长文可以进入完整阅读页。
class MomentCard extends StatefulWidget {
  final Moment moment;
  final String nickname;
  final String? avatarUrl;
  final String partnerNickname;
  final bool isSelf;
  final VoidCallback? onEdit;
  final VoidCallback? onComment;
  final VoidCallback? onOpenReading;
  final void Function(Comment comment)? onDeleteComment;
  final void Function(Comment? parentComment)? onReplyComment;
  final bool expandedReading;
  final String? focusCommentId;
  final ValueChanged<String>? onCommentRevealed;
  final bool showInlineAction;

  const MomentCard({
    super.key,
    required this.moment,
    this.nickname = '',
    this.avatarUrl,
    this.partnerNickname = '',
    this.isSelf = true,
    this.onEdit,
    this.onComment,
    this.onOpenReading,
    this.onDeleteComment,
    this.onReplyComment,
    this.expandedReading = false,
    this.focusCommentId,
    this.onCommentRevealed,
    this.showInlineAction = true,
  });

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  late bool _commentsExpanded;
  final _commentKeys = <String, GlobalKey>{};

  Moment get moment => widget.moment;
  String get _displayName =>
      widget.nickname.isEmpty ? (widget.isSelf ? '我' : 'TA') : widget.nickname;

  @override
  void initState() {
    super.initState();
    _commentsExpanded = widget.expandedReading;
  }

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusCommentId != null) {
      _commentsExpanded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealComment());
    }
  }

  Future<void> _revealComment() async {
    if (!mounted) return;
    final commentId = widget.focusCommentId;
    final target = _commentKeys[commentId]?.currentContext;
    if (target == null) return;
    final object = target.findRenderObject();
    final scrollable = Scrollable.maybeOf(target);
    if (object == null || scrollable == null) return;
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;
    final start = viewport.getOffsetToReveal(object, 0).offset;
    final end = viewport.getOffsetToReveal(object, 1).offset;
    final offset = scrollable.position.pixels;
    // 已在视野中的留言不移动页面；只为视野外的新留言做最小定位。
    if (offset < end - 1 || offset > start + 1) {
      await Scrollable.ensureVisible(
        target,
        alignment: .75,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
    if (mounted && commentId != null && widget.focusCommentId == commentId) {
      widget.onCommentRevealed?.call(commentId);
    }
  }

  String _nickFor(String authorId) => authorId == moment.authorId
      ? _displayName
      : (widget.partnerNickname.isEmpty ? 'TA' : widget.partnerNickname);

  @override
  Widget build(BuildContext context) {
    if (widget.expandedReading) return _buildReadingContent(context);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.hasBoundedHeight ? constraints.maxHeight : 460,
        child: _buildOverview(context, constraints.maxHeight),
      ),
    );
  }

  /// 概览只使用双联页实际分配的高度；正文、照片与操作不会推高页面。
  Widget _buildOverview(BuildContext context, double availableHeight) {
    final height = availableHeight.isFinite ? availableHeight : 460.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compact = height < 260 * textScale;
    final padding = compact ? 8.0 : 12.0;
    final showMetadata = height >= 200 * textScale;
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(
                avatarUrl: widget.avatarUrl,
                size: compact ? 26 : 30,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.momentNickname.copyWith(fontSize: 14),
                    ),
                    if (showMetadata) ...[
                      const SizedBox(height: 2),
                      if (moment.mood != null)
                        _buildMoodBadge(compact: true, showLabel: true)
                      else
                        Text(
                          widget.isSelf ? '我的这一页' : 'TA 的这一页',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (!showMetadata && moment.mood != null) ...[
                const SizedBox(width: 4),
                _buildMoodBadge(compact: true),
              ],
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          Expanded(child: _buildOverviewSummary(context)),
          SizedBox(height: compact ? 4 : 8),
          _buildOverviewActions(context),
        ],
      ),
    );
  }

  Widget _buildOverviewSummary(BuildContext context) {
    final hasPhotos = moment.imageUrls.isNotEmpty;
    return SingleChildScrollView(
      key: PageStorageKey('overview-content-${moment.id}'),
      primary: false,
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPhotos) ...[
            _buildCoverBox(context),
            const SizedBox(height: 10),
          ],
          Text(
            moment.feeling.isEmpty
                ? (hasPhotos ? '今天的片刻，留在照片里。' : '记录了今天的心情。')
                : moment.feeling,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewActions(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.dividerColor)),
      ),
      width: double.infinity,
      child: TextButton(
        onPressed: widget.onOpenReading ?? () => _openReading(context),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '展开日记与留言',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingContent(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(widget.expandedReading ? 20 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(avatarUrl: widget.avatarUrl, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.momentNickname.copyWith(fontSize: 15),
                ),
              ),
              if (moment.mood != null) ...[
                const SizedBox(width: 12),
                _buildMoodBadge(),
              ],
            ],
          ),
          if (moment.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCoverBox(context),
          ],
          if (moment.feeling.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFeeling(),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  DateHelper.toEditTime(moment.updatedAt),
                  style: AppTheme.momentTime.copyWith(
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              if (widget.showInlineAction) ...[
                const SizedBox(width: 12),
                _buildActionButton(),
              ],
            ],
          ),
          if (moment.comments.isNotEmpty) ...[
            const Divider(height: 16, color: AppTheme.dividerColor),
            TextButton(
              onPressed: () =>
                  setState(() => _commentsExpanded = !_commentsExpanded),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${moment.comments.length} 条留言',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Icon(
                    _commentsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_commentsExpanded) _buildComments(context),
          ],
        ],
      ),
    );
  }

  Widget _buildFeeling() => SelectableText(
    moment.feeling,
    style: const TextStyle(
      fontSize: 15,
      color: AppTheme.textPrimary,
      height: 1.75,
    ),
  );
  void _openReading(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (readingContext) {
          return Scaffold(
            appBar: AppBar(title: Text('$_displayName 的日记')),
            body: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: MomentCard(
                      moment: moment,
                      nickname: widget.nickname,
                      avatarUrl: widget.avatarUrl,
                      partnerNickname: widget.partnerNickname,
                      isSelf: widget.isSelf,
                      expandedReading: true,
                      onEdit: widget.onEdit,
                      onComment: widget.onComment,
                      onDeleteComment: widget.onDeleteComment,
                      onReplyComment: widget.onReplyComment,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoodBadge({bool compact = false, bool showLabel = false}) {
    final moodColor = AppTheme.moodColor(moment.mood!);
    return Container(
      height: compact ? null : 30,
      alignment: compact ? null : Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 13,
        vertical: compact ? 2 : 0,
      ),
      decoration: BoxDecoration(
        gradient: AppTheme.moodGradient(moment.mood!),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: moodColor.withValues(alpha: .8)),
      ),
      child: Text(
        '${showLabel ? '心情 ' : ''}${moment.mood}分',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 11 : 13,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(
              color: Color(0x806C5670),
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() => TextButton.icon(
    onPressed: widget.isSelf ? widget.onEdit : widget.onComment,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      backgroundColor: AppTheme.softSurface,
      foregroundColor: AppTheme.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    icon: Icon(
      widget.isSelf ? Icons.edit_outlined : Icons.chat_bubble_outline_rounded,
      size: 15,
    ),
    label: Text(
      widget.isSelf ? AppStrings.editButton : '留言',
      style: const TextStyle(fontSize: 12),
    ),
  );

  Widget _buildComments(BuildContext context) {
    final ids = moment.comments.map((comment) => comment.id).toSet();
    final replies = <String, List<Comment>>{};
    for (final comment in moment.comments) {
      if (comment.replyTo != null) {
        replies.putIfAbsent(comment.replyTo!, () => []).add(comment);
      }
    }
    final topLevel = moment.comments
        .where(
          (comment) =>
              comment.replyTo == null || !ids.contains(comment.replyTo),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in topLevel)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.softSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _buildCommentTree(context, comment, replies),
          ),
      ],
    );
  }

  Widget _buildCommentTree(
    BuildContext context,
    Comment comment,
    Map<String, List<Comment>> replies,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: _commentKeys.putIfAbsent(comment.id, () => GlobalKey()),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          decoration: BoxDecoration(
            color: comment.id == widget.focusCommentId
                ? const Color(0xFFF5E5EF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppTheme.textPrimary,
              ),
              children: [
                TextSpan(
                  text: '${_nickFor(comment.authorId)}：',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
                TextSpan(text: comment.content),
              ],
            ),
            onTap: () => _showCommentActions(context, comment),
          ),
        ),
        for (final child in replies[comment.id] ?? <Comment>[])
          _buildCommentTree(context, child, replies),
      ],
    );
  }

  void _showCommentActions(BuildContext context, Comment comment) {
    final isMyComment = comment.authorId == moment.authorId
        ? widget.isSelf
        : !widget.isSelf;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                '留言：${comment.content}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            if (widget.onReplyComment != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('回复'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onReplyComment?.call(comment);
                },
              ),
            if (isMyComment && widget.onDeleteComment != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.dangerColor,
                ),
                title: const Text(
                  '删除',
                  style: TextStyle(color: AppTheme.dangerColor),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onDeleteComment?.call(comment);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverBox(BuildContext context) {
    final urls = moment.imageUrls;
    return GestureDetector(
      onTap: () => showImageGallery(context, urls),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                cacheManager: PrivateImageCache(),
                imageUrl: urls.first,
                fit: BoxFit.cover,
                placeholder: (_, _) => _imagePlaceholder(),
                errorWidget: (_, _, _) => _imagePlaceholder(),
              ),
              _MomentCoverLiveBadge(url: urls.first),
              if (urls.length > 1)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${urls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => const ColoredBox(
    color: AppTheme.softSurface,
    child: Center(
      child: Icon(Icons.image_outlined, color: AppTheme.textSecondary),
    ),
  );
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
    if (mounted) {
      setState(() => _isMotion = isMotion);
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
