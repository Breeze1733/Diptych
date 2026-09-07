import 'package:flutter/material.dart';

/// 对角线斜杠绘制器：用于在未勾选实况的角标上画一条清晰的对角斜杠
class DiagonalSlashPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const DiagonalSlashPainter({
    this.color = Colors.white,
    this.strokeWidth = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 阴影底线，确保在任何背景或文字上都极高对比度
    final shadowPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = strokeWidth + 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(3, size.height - 3),
      Offset(size.width - 3, 3),
      shadowPaint,
    );

    // 主斜杠线
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(3, size.height - 3),
      Offset(size.width - 3, 3),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant DiagonalSlashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// 实况照片缩略图角标与状态标识
/// - 有选择实况（isLiveSelected == true）：正常看到「实况」文字与图标（无斜杠）
/// - 未选择实况（isLiveSelected == false）：保留角标，但画有一条对角斜杠
/// - 点击可直接在缩略图上切换实况与静态上传模式
class LivePhotoBadge extends StatelessWidget {
  final bool isLiveSelected;
  final VoidCallback? onTap;
  final double fontSize;
  final double iconSize;

  const LivePhotoBadge({
    super.key,
    required this.isLiveSelected,
    this.onTap,
    this.fontSize = 9.5,
    this.iconSize = 11.0,
  });

  @override
  Widget build(BuildContext context) {
    final badgeWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isLiveSelected
            ? const Color(0xFF07C160).withAlpha(230)
            : Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLiveSelected ? Colors.white70 : Colors.white38,
          width: 0.8,
        ),
      ),
      child: CustomPaint(
        foregroundPainter: isLiveSelected
            ? null
            : const DiagonalSlashPainter(color: Colors.white, strokeWidth: 1.6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLiveSelected
                  ? Icons.motion_photos_on
                  : Icons.motion_photos_off_outlined,
              size: iconSize,
              color: Colors.white,
            ),
            const SizedBox(width: 3),
            Text(
              '实况',
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return badgeWidget;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: badgeWidget,
    );
  }
}
