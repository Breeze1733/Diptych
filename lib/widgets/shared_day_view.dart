import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';
import 'shared_diary_document.dart';

/// 共记模式的单页日视图。与旧双联并行存在，不复用 MomentCard。
class SharedDayView extends StatelessWidget {
  final SharedMoment moment;
  final double cardOpacity;
  final VoidCallback onOpenReading;
  final VoidCallback onEdit;
  final VoidCallback? onOpenLegacy;

  const SharedDayView({
    super.key,
    required this.moment,
    required this.cardOpacity,
    required this.onOpenReading,
    required this.onEdit,
    this.onOpenLegacy,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Container(
          key: const ValueKey('shared-diary-page'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor.withValues(
              alpha: cardOpacity.clamp(.55, .88),
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .42)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '我们的共记',
                      style: TextStyle(
                        fontSize: 14,
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
      ),
    );
  }
}
