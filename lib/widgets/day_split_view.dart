import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/moment.dart';
import 'avatar_widget.dart';
import 'moment_card.dart';

/// 双联纸面铺满可用区域，壁纸统一从半透明纸面下透出。
class DaySplitView extends StatelessWidget {
  final Moment? myMoment;
  final Moment? partnerMoment;
  final String myNickname;
  final String partnerNickname;
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;
  final VoidCallback? onCreateMyMoment;
  final ValueChanged<Moment>? onOpenReading;
  final double cardOpacity;

  const DaySplitView({
    super.key,
    this.myMoment,
    this.partnerMoment,
    this.myNickname = '',
    this.partnerNickname = '',
    this.myAvatarUrl,
    this.partnerAvatarUrl,
    this.onCreateMyMoment,
    this.onOpenReading,
    required this.cardOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final showFloatingCreate =
        myMoment == null && partnerMoment == null && onCreateMyMoment != null;
    return Expanded(
      child: ColoredBox(
        color: AppTheme.surfaceColor.withValues(alpha: cardOpacity),
        child: Stack(
          key: const ValueKey('diary-split-page'),
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildColumn(
                    moment: myMoment,
                    nickname: myNickname,
                    partnerNickname: partnerNickname,
                    avatarUrl: myAvatarUrl,
                    isSelf: true,
                    showCreateButton: !showFloatingCreate,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.dividerColor,
                ),
                Expanded(
                  child: _buildColumn(
                    moment: partnerMoment,
                    nickname: partnerNickname,
                    partnerNickname: myNickname,
                    avatarUrl: partnerAvatarUrl,
                    isSelf: false,
                  ),
                ),
              ],
            ),
            if (showFloatingCreate)
              Positioned(
                left: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  key: const ValueKey('create-diary-fab'),
                  heroTag: 'create-diary',
                  onPressed: onCreateMyMoment,
                  label: const Text('写日记'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn({
    required Moment? moment,
    required String nickname,
    required String partnerNickname,
    required String? avatarUrl,
    required bool isSelf,
    bool showCreateButton = true,
  }) {
    if (moment != null) {
      return MomentCard(
        key: ValueKey(moment.id),
        moment: moment,
        nickname: nickname,
        avatarUrl: avatarUrl,
        partnerNickname: partnerNickname,
        isSelf: isSelf,
        onOpenReading: onOpenReading == null
            ? null
            : () => onOpenReading!(moment),
      );
    }

    final displayName = nickname.isEmpty ? (isSelf ? '我' : 'TA') : nickname;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = height < 260 * textScale;
        return Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            children: [
              if (height >= 180 * textScale) ...[
                AvatarWidget(avatarUrl: avatarUrl, size: compact ? 28 : 36),
                SizedBox(height: compact ? 6 : 8),
              ],
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(
                  isSelf ? '我的这一页' : 'TA 的这一页',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) {
                    final showPrompt = area.maxHeight >= 60 * textScale;
                    final imageBudget =
                        (area.maxHeight - (showPrompt ? 32 * textScale : 0))
                            .clamp(0.0, 80.0);
                    final imageSize = (area.maxWidth * .7).clamp(
                      0.0,
                      imageBudget,
                    );
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          isSelf
                              ? 'assets/not_posted_self.png'
                              : 'assets/not_posted_partner.png',
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                        if (showPrompt) ...[
                          const SizedBox(height: 8),
                          Text(
                            isSelf ? '今天，想记下什么？' : '等 TA 写下今天',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              if (isSelf && showCreateButton && onCreateMyMoment != null)
                OutlinedButton(
                  onPressed: onCreateMyMoment,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('写日记'),
                ),
            ],
          ),
        );
      },
    );
  }
}
