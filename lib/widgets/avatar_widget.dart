import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 头像组件
class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String nickname;
  final double size;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    required this.nickname,
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
          placeholder: (_, __) => _buildFallback(),
          errorWidget: (_, __, ___) => _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        nickname.isNotEmpty ? nickname[0] : '?',
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
