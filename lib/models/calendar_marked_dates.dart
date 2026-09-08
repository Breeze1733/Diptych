import '../utils/date_helper.dart';

/// 日期记录状态
enum CalendarDateStatus {
  none,  // 双方均未记录
  userA, // 仅用户 A 记录 (#4f46e5)
  userB, // 仅用户 B 记录 (#e11d48)
  both,  // 双人同记 (135° 渐变)
}

/// 日历标记日期数据（维护用户 A 与用户 B 的记录日期集合）
class CalendarMarkedDates {
  final Set<String> userADates;
  final Set<String> userBDates;

  const CalendarMarkedDates({
    required this.userADates,
    required this.userBDates,
  });

  factory CalendarMarkedDates.empty() {
    return const CalendarMarkedDates(
      userADates: {},
      userBDates: {},
    );
  }

  /// 获取指定日期的记录状态
  CalendarDateStatus getStatus(DateTime date) {
    final dateStr = DateHelper.toDateStr(date);
    final hasA = userADates.contains(dateStr);
    final hasB = userBDates.contains(dateStr);
    if (hasA && hasB) return CalendarDateStatus.both;
    if (hasA) return CalendarDateStatus.userA;
    if (hasB) return CalendarDateStatus.userB;
    return CalendarDateStatus.none;
  }

}