import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

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
      return const SizedBox.shrink(); // 无壁纸 → 保持默认背景，不占位不转圈
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            // 加载/失败都用背景色兜底，绝不显示转圈
            placeholder: (_, _) => const ColoredBox(color: AppTheme.backgroundColor),
            errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.backgroundColor),
          ),
          Container(color: Colors.white.withValues(alpha: (1 - opacity).clamp(0.0, 1.0))),
        ],
      ),
    );
  }
}
