import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/moment.dart';
import '../utils/date_helper.dart';
import 'auth_provider.dart';
import 'selected_date_provider.dart';

/// 选定日期的双方动态（用于日视图分屏）
/// 返回 Map: { "myMoment": Moment?, "partnerMoment": Moment? }
final dayMomentsProvider = FutureProvider<Map<String, Moment?>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);
  final dateStr = DateHelper.toDateStr(selectedDate);
  final currentUser = ref.watch(currentUserProvider);
  final partner = ref.watch(partnerUserProvider);

  if (currentUser == null || partner == null) {
    return {'myMoment': null, 'partnerMoment': null};
  }

  final apiService = ref.read(apiServiceProvider);

  final moments = await apiService.getDayMoments(dateStr, [currentUser.uid, partner.uid]);

  Moment? myMoment;
  Moment? partnerMoment;

  for (final m in moments) {
    if (m.authorId == currentUser.uid) {
      myMoment = m;
    } else if (m.authorId == partner.uid) {
      partnerMoment = m;
    }
  }

  return {'myMoment': myMoment, 'partnerMoment': partnerMoment};
});

/// 当前用户有动态的日期列表（用于日历标记点）
final markedDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  final apiService = ref.read(apiServiceProvider);
  final dateStrs = await apiService.getDatesWithMoments(currentUser.uid);
  return dateStrs.map((s) => DateHelper.parseDateStr(s)).toList();
});
