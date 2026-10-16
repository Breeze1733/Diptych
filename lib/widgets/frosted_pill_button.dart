import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// 兼容旧入口的墨蓝主操作按钮，保持原有尺寸和调用方式。
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
    final borderRadius = BorderRadius.circular(14);
    final icon = label.contains('日记') || label.contains('编辑')
        ? Icons.edit_outlined
        : Icons.add_rounded;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: AppTheme.primaryColor,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: AppTheme.surfaceColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.surfaceColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
