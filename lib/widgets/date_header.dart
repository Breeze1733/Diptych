import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../utils/date_helper.dart';

/// A single, compact row for the selected date and day navigation.
class DateHeader extends StatelessWidget {
  final String dateText;
  final DateTime? date;
  final VoidCallback onCalendarTap;
  final VoidCallback? onPreviousDay;
  final VoidCallback? onNextDay;
  final double scale;

  const DateHeader({
    super.key,
    required this.dateText,
    required this.onCalendarTap,
    this.date,
    this.onPreviousDay,
    this.onNextDay,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final title = date == null
        ? dateText.replaceFirst(RegExp(r'\s+星期.*$'), '')
        : DateHelper.toDateStr(date!).replaceAll('-', '.');
    return Material(
      color: AppTheme.surfaceColor.withAlpha(235),
      child: Row(
        children: [
          IconButton(
            onPressed: onPreviousDay,
            tooltip: '前一天',
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: onCalendarTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 17),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNextDay,
            tooltip: '后一天',
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
