import 'package:flutter/material.dart';

/// 顶栏：日期显示 + 日历图标按钮
class DateHeader extends StatelessWidget {
  final String dateText;
  final VoidCallback onCalendarTap;

  const DateHeader({
    super.key,
    required this.dateText,
    required this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E5E5), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(dateText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCalendarTap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.calendar_month, size: 22, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
