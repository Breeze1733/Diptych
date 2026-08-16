import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 头像组件
class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => _buildFallback(),
          errorWidget: (_, _, _) => _buildFallback(),
        ),
      );
    }
    // 无头像：显示空白圆（不带任何文字）
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
    );
  }
}
