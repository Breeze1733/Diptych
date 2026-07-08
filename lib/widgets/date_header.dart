import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/day_moment_provider.dart';

/// 顶栏：日期显示 + 刷新按钮 + 日历图标按钮
class DateHeader extends ConsumerWidget {
  final String dateText;
  final VoidCallback onCalendarTap;

  const DateHeader({
    super.key,
    required this.dateText,
    required this.onCalendarTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendOnline = ref.watch(backendOnlineProvider);

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
          // 刷新按钮
          GestureDetector(
            onTap: backendOnline
                ? () => ref.read(refreshTriggerProvider.notifier).state++
                : null,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: backendOnline ? Colors.grey[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.refresh,
                size: 20,
                color: backendOnline ? Colors.grey[700] : Colors.grey[400],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 日历按钮
          GestureDetector(
            onTap: onCalendarTap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.calendar_month, size: 20, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
