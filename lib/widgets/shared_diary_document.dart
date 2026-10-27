import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';
import 'image_download_placeholder.dart';
import 'image_gallery.dart';
import 'private_network_image.dart';

/// 共记正文的只读渲染。文字与图片都按 A / B 的固定颜色标明作者。
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
    if (moment.blocks.isEmpty) {
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

    final children = <Widget>[];
    var index = 0;
    var imageGroup = 0;
    while (index < moment.blocks.length) {
      final block = moment.blocks[index];
      if (block.type == SharedMomentBlockType.text) {
        children.add(_TextBlock(block: block, compact: compact));
        index++;
      } else {
        final images = <SharedMomentBlock>[];
        while (index < moment.blocks.length &&
            moment.blocks[index].type == SharedMomentBlockType.image) {
          images.add(moment.blocks[index]);
          index++;
        }
        children.add(
          _ImageBlockGrid(
            key: ValueKey('shared-image-grid-${imageGroup++}'),
            images: images,
            allImages: moment.blocks
                .where((item) => item.type == SharedMomentBlockType.image)
                .toList(growable: false),
          ),
        );
      }
      if (index < moment.blocks.length) {
        children.add(SizedBox(height: compact ? 10 : 14));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _TextBlock extends StatelessWidget {
  final SharedMomentBlock block;
  final bool compact;

  const _TextBlock({required this.block, required this.compact});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.sharedAuthorColor(block.authorId);
    return Container(
      key: ValueKey('shared-text-${block.id}'),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 9 : 12,
        compact ? 10 : 14,
        compact ? 9 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.authorId,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            block.text,
            style: TextStyle(
              color: color,
              fontSize: compact ? 14 : 16,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBlockGrid extends StatelessWidget {
  final List<SharedMomentBlock> images;
  final List<SharedMomentBlock> allImages;

  const _ImageBlockGrid({
    super.key,
    required this.images,
    required this.allImages,
  });

  @override
  Widget build(BuildContext context) {
    final urls = allImages.map((item) => item.imageUrl).toList(growable: false);
    return GridView.builder(
      primary: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final block = images[index];
        final color = AppTheme.sharedAuthorColor(block.authorId);
        final globalIndex = allImages.indexWhere((item) => item.id == block.id);
        return GestureDetector(
          key: ValueKey('shared-image-${block.id}'),
          onTap: () => showFullScreenPreview(
            context,
            urls: urls,
            initialIndex: globalIndex < 0 ? 0 : globalIndex,
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PrivateNetworkImage(
                    imageUrl: block.imageUrl,
                    usePreview: true,
                    fit: BoxFit.cover,
                    placeholder: (_, url) => ImageDownloadPlaceholder(url: url),
                    errorWidget: (_, _, _) => const ColoredBox(
                      color: AppTheme.softSurface,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(7),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          block.authorId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
