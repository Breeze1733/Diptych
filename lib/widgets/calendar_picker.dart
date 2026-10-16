import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/calendar_marked_dates.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../utils/date_helper.dart';

/// 日历以原有蓝粉圆形色块表示双方记录，双色渐变表示双方同记。
class CalendarPicker extends ConsumerStatefulWidget {
  final DateTime selectedDate;

  const CalendarPicker({super.key, required this.selectedDate});

  static DateTime get firstDate => DateTime(2024, 1, 1);

  /// 与日记页面保持一致，凌晨六点前仍属于前一天。
  static DateTime get lastDate {
    final today = DateHelper.effectiveNow;
    return DateTime(today.year, today.month, today.day);
  }

  static DateTime clampDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized.isBefore(firstDate)) return firstDate;
    if (normalized.isAfter(lastDate)) return lastDate;
    return normalized;
  }

  /// 显示日历选择弹窗，返回选中的日期，null 表示取消。
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime selectedDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierColor: AppTheme.primaryColor.withValues(alpha: 0.24),
      builder: (_) => CalendarPicker(selectedDate: selectedDate),
    );
  }

  @override
  ConsumerState<CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends ConsumerState<CalendarPicker> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  bool _isRefreshing = false;

  // 用户 A/B 的颜色绑定沿用记录模型，不随当前登录账号改变。
  static const _colorUserA = Color(0xFF38BDF8);
  static const _colorUserB = Color(0xFFFDA4AF);

  @override
  void initState() {
    super.initState();
    _selectedDay = CalendarPicker.clampDate(widget.selectedDate);
    _focusedDay = _selectedDay;
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await syncCalendarMarkedDatesFromNetwork(ref, throwOnError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已同步最新日记记录'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('日历标记同步失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('同步失败，请检查网络后重试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Widget _buildDayCell(
    DateTime day,
    CalendarMarkedDates markedDates, {
    required bool isSelected,
    required bool isToday,
    required bool isDisabled,
    required String userAName,
    required String userBName,
  }) {
    final status = markedDates.getStatus(day);
    final hasA =
        status == CalendarDateStatus.userA || status == CalendarDateStatus.both;
    final hasB =
        status == CalendarDateStatus.userB || status == CalendarDateStatus.both;
    final hasRecord = hasA || hasB;
    final textColor = isDisabled
        ? AppTheme.textSecondary.withValues(alpha: 0.42)
        : hasRecord
        ? AppTheme.surfaceColor
        : AppTheme.textPrimary;
    final recordNames = [if (hasA) userAName, if (hasB) userBName];

    return Semantics(
      label:
          '${DateHelper.toChineseDate(day)}，'
          '${hasRecord ? '${recordNames.join('、')}的记录' : '未记录'}',
      selected: isSelected,
      enabled: !isDisabled,
      child: ExcludeSemantics(
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: _colorUserA, width: 2)
                  : isToday && !hasRecord
                  ? Border.all(color: _colorUserA.withValues(alpha: 0.6))
                  : null,
            ),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasA && hasB
                    ? null
                    : hasA
                    ? _colorUserA
                    : hasB
                    ? _colorUserB
                    : isSelected
                    ? _colorUserA.withValues(alpha: 0.12)
                    : null,
                gradient: hasA && hasB
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_colorUserA, _colorUserB],
                      )
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasRecord || isSelected || isToday
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markedDatesAsync = ref.watch(markedDatesProvider);
    final markedDates = markedDatesAsync.value ?? CalendarMarkedDates.empty();
    final effectiveToday = CalendarPicker.lastDate;
    final currentUser = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    String nameFor(String uid) {
      final nickname = currentUser?.uid == uid
          ? currentUser?.nickname
          : partner?.uid == uid
          ? partner?.nickname
          : null;
      final trimmed = nickname?.trim();
      return trimmed == null || trimmed.isEmpty ? '用户$uid' : trimmed;
    }

    final userAName = nameFor('A');
    final userBName = nameFor('B');

    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppTheme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      AppStrings.selectDate,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: _isRefreshing
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 21),
                            color: AppTheme.textSecondary,
                            tooltip: '联网同步记录',
                            onPressed: _handleRefresh,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TableCalendar(
                firstDay: CalendarPicker.firstDate,
                lastDay: effectiveToday,
                focusedDay: CalendarPicker.clampDate(_focusedDay),
                currentDay: effectiveToday,
                startingDayOfWeek: StartingDayOfWeek.monday,
                rowHeight: 46,
                daysOfWeekHeight: 28,
                selectedDayPredicate: (day) =>
                    DateHelper.isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = CalendarPicker.clampDate(selectedDay);
                    _focusedDay = CalendarPicker.clampDate(focusedDay);
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = CalendarPicker.clampDate(focusedDay);
                },
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  headerPadding: const EdgeInsets.symmetric(vertical: 4),
                  leftChevronIcon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  rightChevronIcon: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  titleTextStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  titleTextFormatter: (date, locale) =>
                      '${date.year}年${date.month}月',
                ),
                calendarBuilders: CalendarBuilders(
                  dowBuilder: (context, day) {
                    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
                    return Center(
                      child: Text(
                        weekdays[day.weekday - 1],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                  },
                  defaultBuilder: (context, day, focusedDay) => _buildDayCell(
                    day,
                    markedDates,
                    isSelected: false,
                    isToday: false,
                    isDisabled: false,
                    userAName: userAName,
                    userBName: userBName,
                  ),
                  selectedBuilder: (context, day, focusedDay) => _buildDayCell(
                    day,
                    markedDates,
                    isSelected: true,
                    isToday: DateHelper.isSameDay(day, effectiveToday),
                    isDisabled: false,
                    userAName: userAName,
                    userBName: userBName,
                  ),
                  todayBuilder: (context, day, focusedDay) => _buildDayCell(
                    day,
                    markedDates,
                    isSelected: DateHelper.isSameDay(day, _selectedDay),
                    isToday: true,
                    isDisabled: false,
                    userAName: userAName,
                    userBName: userBName,
                  ),
                  outsideBuilder: (context, day, focusedDay) =>
                      const SizedBox.shrink(),
                  disabledBuilder: (context, day, focusedDay) => _buildDayCell(
                    day,
                    markedDates,
                    isSelected: false,
                    isToday: false,
                    isDisabled: true,
                    userAName: userAName,
                    userBName: userBName,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppStrings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      CalendarPicker.clampDate(_selectedDay),
                    ),
                    child: Text(AppStrings.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
