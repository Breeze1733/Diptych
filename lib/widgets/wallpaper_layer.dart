import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../services/private_image_cache.dart';
import 'image_download_placeholder.dart';
import 'private_network_image.dart';

/// 壁纸背景层：永远放在页面最底层，不拦截手势、不遮挡内容。
///
/// [opacity] 0~1：壁纸不透明度。1 = 壁纸完全不透明（默认）；0 = 壁纸完全透明。
/// 半透明白色遮罩叠加在壁纸上：不透明度越低，遮罩越白、壁纸越淡，
/// 避免壁纸与文字/卡片混淆。
class WallpaperLayer extends StatelessWidget {
  final String url;
  final double opacity;

  const WallpaperLayer({super.key, required this.url, required this.opacity});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const IgnorePointer(
        child: ColoredBox(color: AppTheme.backgroundColor),
      );
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          PrivateNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, url) => ImageDownloadPlaceholder(
              url: PrivateImageCache().progressKey(url, original: true),
              backgroundColor: AppTheme.backgroundColor,
            ),
            errorWidget: (_, _, _) =>
                const ColoredBox(color: AppTheme.backgroundColor),
          ),
          Container(
            color: Colors.white.withValues(
              alpha: (1 - opacity).clamp(0.0, 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
