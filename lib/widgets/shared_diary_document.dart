import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';
import 'image_download_placeholder.dart';
import 'image_gallery.dart';
import 'private_network_image.dart';

/// 共记的阅读投影：数据库仍按 block 保存，界面只呈现“图片 + 一篇连续正文”。
class SharedDiaryDocument extends StatelessWidget {
  final SharedMoment moment;
  final bool compact;

  const SharedDiaryDocument({
    super.key,
    required this.moment,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final images = moment.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .toList(growable: false);
    final textRuns = moment.blocks
        .where((block) => block.type == SharedMomentBlockType.text)
        .toList(growable: false);

    if (images.isEmpty && textRuns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 46,
              color: AppTheme.textSecondary,
            ),
            SizedBox(height: 14),
            Text(
              '这页共记还是空白的\n从一段话或一张照片开始吧',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          _SharedImageGrid(
            key: const ValueKey('shared-image-grid'),
            images: images,
            compact: compact,
          ),
        if (images.isNotEmpty && textRuns.isNotEmpty)
          SizedBox(height: compact ? 12 : 20),
        if (textRuns.isNotEmpty)
          SelectableText.rich(
            key: const ValueKey('shared-continuous-text'),
            TextSpan(
              children: [
                for (final block in textRuns)
                  TextSpan(
                    text: block.text,
                    style: TextStyle(
                      color: AppTheme.sharedAuthorColor(block.authorId),
                    ),
                  ),
              ],
            ),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: compact ? 14 : 16,
              height: compact ? 1.65 : 1.78,
            ),
          ),
      ],
    );
  }
}

class _SharedImageGrid extends StatefulWidget {
  final List<SharedMomentBlock> images;
  final bool compact;

  const _SharedImageGrid({
    super.key,
    required this.images,
    required this.compact,
  });

  @override
  State<_SharedImageGrid> createState() => _SharedImageGridState();
}

class _SharedImageGridState extends State<_SharedImageGrid> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.images
        .map((item) => item.imageUrl)
        .toList(growable: false);
    final spacing = widget.compact ? 6.0 : 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileExtent = math.max(
          .1,
          (constraints.maxWidth - spacing * 2) / 3,
        );
        final rows = math.min(2, (widget.images.length / 3).ceil());
        final height = tileExtent * rows + spacing * math.max(0, rows - 1);
        final scrollable = widget.images.length > 6;
        return SizedBox(
          height: height,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: scrollable,
            child: GridView.builder(
              controller: _scrollController,
              primary: false,
              padding: EdgeInsets.zero,
              physics: scrollable
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: tileExtent,
              ),
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final block = widget.images[index];
                final color = AppTheme.sharedAuthorColor(block.authorId);
                return GestureDetector(
                  key: ValueKey('shared-image-${block.id}'),
                  onTap: () => showFullScreenPreview(
                    context,
                    urls: urls,
                    initialIndex: index,
                  ),
                  child: Semantics(
                    label: '${block.authorId} 添加的照片',
                    button: true,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: color, width: 3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: PrivateNetworkImage(
                          imageUrl: block.imageUrl,
                          usePreview: true,
                          fit: BoxFit.cover,
                          placeholder: (_, url) =>
                              ImageDownloadPlaceholder(url: url),
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: AppTheme.softSurface,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
