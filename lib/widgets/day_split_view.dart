import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';

import 'moment_card.dart';

/// 单日 1:1 分屏视图
/// 左侧：当前用户的动态，右侧：对方的动态（或盲盒遮罩）
class DaySplitView extends StatelessWidget {
  final Moment? myMoment;
  final Moment? partnerMoment;
  final String myNickname;
  final String partnerNickname;
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;
  final VoidCallback? onEditMyMoment;
  final VoidCallback? onCommentPartner;
  final void Function(Comment comment)? onDeleteMyComment;
  final void Function(Comment comment)? onDeletePartnerComment;
  final void Function(Comment? parentComment)? onReplyMyComment;
  final void Function(Comment? parentComment)? onReplyPartnerComment;

  const DaySplitView({
    super.key,
    this.myMoment,
    this.partnerMoment,
    this.myNickname = '',
    this.partnerNickname = '',
    this.myAvatarUrl,
    this.partnerAvatarUrl,
    this.onEditMyMoment,
    this.onCommentPartner,
    this.onDeleteMyComment,
    this.onDeletePartnerComment,
    this.onReplyMyComment,
    this.onReplyPartnerComment,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左列：自己的动态
          Expanded(
            child: _buildColumn(
              moment: myMoment,
              nickname: myNickname,
              partnerNickname: partnerNickname,
              avatarUrl: myAvatarUrl,
              isSelf: true,
              onEdit: onEditMyMoment,
              onComment: null,
              onDeleteComment: onDeleteMyComment,
              onReplyComment: onReplyMyComment,
            ),
          ),
          // 中间分隔线
          Container(
            width: 1,
            color: AppTheme.dividerColor,
          ),
          // 右列：对方的动态
          Expanded(
            child: _buildColumn(
              moment: partnerMoment,
              nickname: partnerNickname,
              partnerNickname: myNickname,
              avatarUrl: partnerAvatarUrl,
              isSelf: false,
              onEdit: null,
              onComment: onCommentPartner,
              onDeleteComment: onDeletePartnerComment,
              onReplyComment: onReplyPartnerComment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn({
    required Moment? moment,
    required String nickname,
    required String partnerNickname,
    required String? avatarUrl,
    required bool isSelf,
    VoidCallback? onEdit,
    VoidCallback? onComment,
    void Function(Comment comment)? onDeleteComment,
    void Function(Comment? parentComment)? onReplyComment,
  }) {
    if (moment != null) {
      // 有动态，正常显示
      return SingleChildScrollView(
        child: MomentCard(
          moment: moment,
          nickname: nickname,
          avatarUrl: avatarUrl,
          partnerNickname: partnerNickname,
          isSelf: isSelf,
          onEdit: onEdit,
          onComment: onComment,
          onDeleteComment: onDeleteComment,
          onReplyComment: onReplyComment,
        ),
      );
    }

    if (isSelf) {
      // 自己还未发布
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note, size: 40, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text(
                AppStrings.noPostPlaceholder,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // 对方未发布 → 空白
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              AppStrings.noPostPlaceholder,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
