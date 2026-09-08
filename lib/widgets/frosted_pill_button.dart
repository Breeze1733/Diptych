import 'dart:ui';
import 'package:flutter/material.dart';

/// 磨砂玻璃胶囊悬浮按钮（用于“写日记”、“创建话题”等操作按钮，保持尺寸与位置绝对一致）
class FrostedPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;

  const FrostedPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.width = 104,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final double radius = height / 2;
    final borderRadius = BorderRadius.circular(radius);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(200),
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withAlpha(180),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
