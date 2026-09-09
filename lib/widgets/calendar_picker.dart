import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../constants/strings.dart';
import '../models/calendar_marked_dates.dart';
import '../providers/day_moment_provider.dart';
import '../utils/date_helper.dart';

/// 日历选择器弹窗（透明磨砂玻璃质感，正圆形双人状态配色与紧凑行间距）
class CalendarPicker extends ConsumerStatefulWidget {
  final DateTime selectedDate;

  const CalendarPicker({
    super.key,
    required this.selectedDate,
  });

  /// 显示日历选择弹窗，返回选中的日期，null 表示取消
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime selectedDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withAlpha(60),
      builder: (_) => CalendarPicker(
        selectedDate: selectedDate,
      ),
    );
  }

  @override
  ConsumerState<CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends ConsumerState<CalendarPicker> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  bool _isRefreshing = false;

  // 状态配色方案（严格绑定用户 ID：晴空蓝 + 柔嫩浅粉）
  static const Color _colorUserA = Color(0xFF38BDF8); // 晴空浅蓝 (Sky Blue)
  static const Color _colorUserB = Color(0xFFFDA4AF); // 柔嫩浅粉 (Soft Light Pink)

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDate;
    _selectedDay = widget.selectedDate;
  }

  /// 联网刷新所有日期的日记情况
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    try {
      await syncCalendarMarkedDatesFromNetwork(ref, throwOnError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已同步最新日记记录'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// 构建正圆形统一单元格
  Widget _buildDayCell(
    BuildContext context,
    DateTime day,
    CalendarMarkedDates markedDates, {
    required bool isSelected,
    required bool isToday,
    required bool isDisabled,
  }) {
    final status = markedDates.getStatus(day);
    final hasRecord = status != CalendarDateStatus.none;

    BoxDecoration? innerDecoration;
    Color textColor;

    if (hasRecord) {
      textColor = Colors.white;
      switch (status) {
        case CalendarDateStatus.both:
          // 135° 双色渐变 + 紫色微光阴影 (正圆形)
          innerDecoration = BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_colorUserA, _colorUserB],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA78BFA).withAlpha(80),
                blurRadius: 6,
                spreadRadius: 0.5,
                offset: const Offset(0, 1.5),
              ),
            ],
          );
          break;
        case CalendarDateStatus.userA:
          // 纯蓝/靛青色色块，无边框 (正圆形)
          innerDecoration = const BoxDecoration(
            shape: BoxShape.circle,
            color: _colorUserA,
          );
          break;
        case CalendarDateStatus.userB:
          // 纯玫红/粉红色块，无边框 (正圆形)
          innerDecoration = const BoxDecoration(
            shape: BoxShape.circle,
            color: _colorUserB,
          );
          break;
        case CalendarDateStatus.none:
          break;
      }
    } else {
      if (isDisabled) {
        textColor = Colors.grey[400]!;
      } else if (isToday) {
        textColor = _colorUserA;
      } else {
        textColor = Colors.black87;
      }
    }

    // 正圆形外圈高亮轮廓环 / 偏白色发亮边框（柔和微光，不突兀）
    BoxDecoration? outerDecoration;
    if (isSelected) {
      outerDecoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withAlpha(220),
            blurRadius: 6,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: const Color(0xFF64748B).withAlpha(60),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      );
    } else if (isToday && !hasRecord) {
      outerDecoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF94A3B8).withAlpha(120),
          width: 1.2,
        ),
      );
    }

    final Widget textWidget = Center(
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: textColor,
          fontSize: 13.5,
          fontWeight: (hasRecord || isSelected || isToday)
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
    );

    return Center(
      child: Container(
        width: 32,
        height: 32,
        decoration: outerDecoration,
        padding: isSelected ? const EdgeInsets.all(2) : EdgeInsets.zero,
        child: innerDecoration != null
            ? Container(
                decoration: innerDecoration,
                child: textWidget,
              )
            : textWidget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markedDatesAsync = ref.watch(markedDatesProvider);
    final markedDates = markedDatesAsync.value ?? CalendarMarkedDates.empty();

    final dialogRadius = BorderRadius.circular(20);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: dialogRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: dialogRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(210), // 半透明磨砂玻璃白底
                borderRadius: dialogRadius,
                border: Border.all(
                  color: Colors.white.withAlpha(180), // 玻璃高光反光边框
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶栏：标题与右上角刷新按钮
                Row(
                  children: [
                    const SizedBox(width: 36), // 占位保持中间标题完美居中
                    Expanded(
                      child: Center(
                        child: Text(
                          AppStrings.selectDate,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: _isRefreshing
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: '联网同步记录',
                              onPressed: _handleRefresh,
                              splashRadius: 18,
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 日历主体（紧凑行间距）
                TableCalendar(
                  firstDay: DateTime(2024, 1, 1),
                  lastDay: DateTime.now(),
                  focusedDay: _focusedDay,
                  rowHeight: 38, // 缩小每一行高度，去除多余留白，整体更紧凑
                  daysOfWeekHeight: 24,
                  selectedDayPredicate: (day) =>
                      DateHelper.isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    headerPadding: const EdgeInsets.symmetric(vertical: 4),
                    titleTextStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    titleTextFormatter: (date, locale) =>
                        '${date.year}年${date.month}月',
                  ),
                  calendarBuilders: CalendarBuilders(
                    // 星期表头：单字中文 一 二 三 四 五 六 日
                    dowBuilder: (context, day) {
                      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
                      final text = weekdays[day.weekday - 1];
                      final isWeekend = day.weekday == DateTime.saturday ||
                          day.weekday == DateTime.sunday;
                      return Center(
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isWeekend ? Colors.grey[500] : Colors.grey[700],
                          ),
                        ),
                      );
                    },
                    defaultBuilder: (context, day, focusedDay) => _buildDayCell(
                      context,
                      day,
                      markedDates,
                      isSelected: false,
                      isToday: false,
                      isDisabled: false,
                    ),
                    selectedBuilder: (context, day, focusedDay) => _buildDayCell(
                      context,
                      day,
                      markedDates,
                      isSelected: true,
                      isToday: DateHelper.isSameDay(day, DateTime.now()),
                      isDisabled: false,
                    ),
                    todayBuilder: (context, day, focusedDay) => _buildDayCell(
                      context,
                      day,
                      markedDates,
                      isSelected: DateHelper.isSameDay(day, _selectedDay),
                      isToday: true,
                      isDisabled: false,
                    ),
                    outsideBuilder: (context, day, focusedDay) =>
                        const SizedBox.shrink(),
                    disabledBuilder: (context, day, focusedDay) => _buildDayCell(
                      context,
                      day,
                      markedDates,
                      isSelected: false,
                      isToday: false,
                      isDisabled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // 按钮行（磨砂玻璃材质）
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildFrostedButton(
                      text: AppStrings.cancel,
                      onTap: () => Navigator.pop(context),
                      textColor: Colors.grey[700]!,
                      bgColor: Colors.white.withAlpha(140),
                      borderColor: Colors.white.withAlpha(200),
                    ),
                    const SizedBox(width: 10),
                    _buildFrostedButton(
                      text: AppStrings.confirm,
                      onTap: () => Navigator.pop(context, _selectedDay),
                      textColor: Colors.white,
                      bgColor: _colorUserA.withAlpha(220),
                      borderColor: Colors.white.withAlpha(200),
                      boxShadow: [
                        BoxShadow(
                          color: _colorUserA.withAlpha(90),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
  Widget _buildFrostedButton({
    required String text,
    required VoidCallback onTap,
    required Color textColor,
    required Color bgColor,
    required Color borderColor,
    List<BoxShadow>? boxShadow,
  }) {
    final btnRadius = BorderRadius.circular(10);
    return Container(
      decoration: BoxDecoration(
        borderRadius: btnRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: btnRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: btnRadius,
              border: Border.all(
                color: borderColor,
                width: 1.2,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: btnRadius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
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