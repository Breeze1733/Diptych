import 'package:flutter/foundation.dart';

import '../models/moment.dart';
import '../utils/date_helper.dart';
import 'api_service.dart';
import 'cache_service.dart';

/// 先提交日记记录，再允许调用方清理被替换的图片；缓存失败不改变发布结果。
class MomentSaveService {
  final ApiService api;
  MomentSaveService(this.api);

  Future<MomentSaveResult> save({
    required String dateStr,
    required String authorId,
    required List<String> imageUrls,
    required String feeling,
    required int? mood,
    Moment? existingMoment,
  }) async {
    final previous =
        existingMoment ?? await api.getMomentByDate(authorId, dateStr);
    final finalUrls =
        previous != null && existingMoment == null && imageUrls.isEmpty
        ? previous.imageUrls
        : imageUrls;
    final String id;
    if (previous != null) {
      await api.updateMoment(previous.id, {
        'image_urls': finalUrls,
        'feeling': feeling,
        'mood': mood,
      });
      id = previous.id;
    } else {
      id = await api.createMoment(
        dateStr: dateStr,
        authorId: authorId,
        imageUrls: finalUrls,
        feeling: feeling,
        mood: mood,
      );
    }
    try {
      final cached = await CacheService.loadDayMoments(dateStr) ?? [];
      final index = cached.indexWhere(
        (m) => m['date_str'] == dateStr && m['author_id'] == authorId,
      );
      final now = DateHelper.toIsoString(DateTime.now());
      final json = <String, dynamic>{
        'id': id,
        'date_str': dateStr,
        'author_id': authorId,
        'image_urls': finalUrls,
        'feeling': feeling,
        'mood': mood,
        'updated_at': now,
        'created_at': index >= 0
            ? cached[index]['created_at']
            : previous == null
            ? now
            : DateHelper.toIsoString(previous.createdAt),
        'comments': index >= 0
            ? cached[index]['comments'] ?? []
            : previous?.comments.map((c) => c.toJson()).toList() ?? [],
      };
      if (index >= 0) {
        cached[index] = json;
      } else {
        cached.add(json);
      }
      await CacheService.saveDayMoments(dateStr, cached);
    } catch (error) {
      debugPrint('[MomentSave] 发布成功，本地缓存更新失败: $error');
    }
    return MomentSaveResult(
      imageUrls: List.unmodifiable(finalUrls),
      removedUrls: [
        for (final old in previous?.imageUrls ?? <String>[])
          if (!finalUrls.contains(old)) old,
      ],
    );
  }
}

class MomentSaveResult {
  final List<String> imageUrls;
  final List<String> removedUrls;
  const MomentSaveResult({required this.imageUrls, required this.removedUrls});
}
