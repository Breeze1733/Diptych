import 'package:intl/intl.dart';

/// 日期格式化工具
class DateHelper {
  DateHelper._();

  /// 日期 → "YYYY-MM-DD"
  static String toDateStr(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// 以 6:00 为界获取"有效今天"——0:00-5:59 算前一天
  static DateTime get effectiveNow {
    final now = DateTime.now();
    if (now.hour < 6) {
      return now.subtract(const Duration(days: 1));
    }
    return now;
  }

  /// 今天的日期字符串（以 6:00 为界）
  static String get todayStr => toDateStr(effectiveNow);

  /// 日期 → "2026年07月05日 星期一"
  static String toChineseDate(DateTime date) {
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final formatted = DateFormat('yyyy年MM月dd日').format(date);
    final weekday = weekdays[date.weekday - 1];
    return '$formatted $weekday';
  }

  /// 判断两个日期是否是同一天
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 判断是否是今天（以 6:00 为界）
  static bool isToday(DateTime date) {
    return isSameDay(date, effectiveNow);
  }

  /// 日期字符串转 DateTime
  static DateTime parseDateStr(String dateStr) {
    return DateFormat('yyyy-MM-dd').parse(dateStr);
  }

  /// 格式化时间戳为简短时间
  static String toShortTime(DateTime date) {
    return DateFormat('HH:mm').format(date.toLocal());
  }

  /// 格式化编辑时间：第一行日期，第二行时间
  static String toEditTime(DateTime date) {
    final local = date.toLocal();
    final dateLine = DateFormat('yyyy年MM月dd日').format(local);
    final timeLine = DateFormat('HH:mm').format(local);
    return '$dateLine\n$timeLine';
  }

  /// 解析后端返回的时间字符串（兼容多种格式）
  static DateTime tryParseDateTime(String value) {
    // 先试 ISO 8601
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    // 再试 MySQL 格式 "2026-07-05 08:38:00"
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse(value);
    } catch (_) {}
    // 再试不带秒 "2026-07-05 08:38"
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(value);
    } catch (_) {}
    return DateTime.now();
  }
}
