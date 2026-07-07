import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/date_helper.dart';

/// 当前选中的查看日期，默认今天（以 6:00 为界）
final selectedDateProvider = StateProvider<DateTime>((ref) => DateHelper.effectiveNow);
