import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';
import 'avatar_widget.dart';
import 'shared_diary_document.dart';

/// 共记模式的单页日视图。与旧双联并行存在，不复用 MomentCard。
class SharedDayView extends StatelessWidget {
  final SharedMoment moment;
  final String userAName;
  final String userBName;
  final String? userAAvatarUrl;
  final String? userBAvatarUrl;
  final double cardOpacity;
  final VoidCallback onOpenReading;
  final VoidCallback onEdit;
  final VoidCallback? onOpenLegacy;

  const SharedDayView({
    super.key,
    required this.moment,
    required this.userAName,
    required this.userBName,
    this.userAAvatarUrl,
    this.userBAvatarUrl,
    required this.cardOpacity,
    required this.onOpenReading,
    required this.onEdit,
    this.onOpenLegacy,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ColoredBox(
        key: const ValueKey('shared-diary-page'),
        color: AppTheme.surfaceColor.withValues(alpha: cardOpacity),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  _AuthorChip(
                    authorId: 'A',
                    name: userAName,
                    avatarUrl: userAAvatarUrl,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  _AuthorChip(
                    authorId: 'B',
                    name: userBName,
                    avatarUrl: userBAvatarUrl,
                  ),
                  const Spacer(),
                  Text(
                    '共记 · v${moment.revision}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey('shared-overview-${moment.id}'),
                padding: const EdgeInsets.all(16),
                child: SharedDiaryDocument(moment: moment, compact: true),
              ),
            ),
            if (onOpenLegacy != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onOpenLegacy,
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('查看保留的旧双联'),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenReading,
                      icon: const Icon(Icons.open_in_full_rounded, size: 17),
                      label: const Text('展开共记'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: Text(moment.blocks.isEmpty ? '开始共写' : '继续共写'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorChip extends StatelessWidget {
  final String authorId;
  final String name;
  final String? avatarUrl;

  const _AuthorChip({
    required this.authorId,
    required this.name,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.sharedAuthorColor(authorId);
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: AvatarWidget(avatarUrl: avatarUrl, size: 26),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name.trim().isEmpty ? '用户$authorId' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
