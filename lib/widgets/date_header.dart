import "package:flutter/material.dart";

/// 顶栏：日期显示 + 日历图标按钮
class DateHeader extends StatelessWidget {
  final String dateText;
  final VoidCallback onCalendarTap;
  final double scale;

  const DateHeader({
    super.key,
    required this.dateText,
    required this.onCalendarTap,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (16 * scale).clamp(8.0, 16.0),
        vertical: (12 * scale).clamp(6.0, 12.0),
      ),
      decoration: const BoxDecoration(
        // 半透明白顶栏：让壁纸能透过显示
        color: Color(0xD9FFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E5E5), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dateText,
                style: TextStyle(
                  fontSize: (16 * scale).clamp(12.0, 16.0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SizedBox(width: (8 * scale).clamp(4.0, 8.0)),
          GestureDetector(
            onTap: onCalendarTap,
            child: Container(
              padding: EdgeInsets.all((6 * scale).clamp(3.0, 6.0)),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular((6 * scale).clamp(4.0, 6.0)),
              ),
              child: Icon(
                Icons.calendar_month,
                size: (22 * scale).clamp(16.0, 22.0),
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
