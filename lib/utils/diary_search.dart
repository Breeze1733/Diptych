import '../models/moment.dart';
import '../models/shared_moment.dart';

enum DiarySearchHitKind { legacy, shared }

/// A presentation-neutral search hit. Legacy and shared records keep their own
/// models and cursors; only these lightweight view records are merged.
class DiarySearchHit {
  final String key;
  final String dateStr;
  final DateTime updatedAt;
  final String sourceLabel;
  final String content;
  final String authorId;
  final DiarySearchHitKind kind;
  final Moment? legacyMoment;
  final SharedMoment? sharedMoment;

  const DiarySearchHit({
    required this.key,
    required this.dateStr,
    required this.updatedAt,
    required this.sourceLabel,
    required this.content,
    required this.authorId,
    required this.kind,
    this.legacyMoment,
    this.sharedMoment,
  });
}

List<DiarySearchHit> buildLegacyMomentSearchHits(
  Iterable<Moment> moments,
  String keyword,
) {
  final query = keyword.toLowerCase();
  final hits = <DiarySearchHit>[];
  for (final moment in moments) {
    if (moment.feeling.toLowerCase().contains(query)) {
      hits.add(
        DiarySearchHit(
          key: 'moment:${moment.id}:feeling',
          dateStr: moment.dateStr,
          updatedAt: moment.updatedAt,
          sourceLabel: '日记',
          content: moment.feeling,
          authorId: moment.authorId,
          kind: DiarySearchHitKind.legacy,
          legacyMoment: moment,
        ),
      );
    }
    for (final comment in moment.comments) {
      if (!comment.content.toLowerCase().contains(query)) continue;
      hits.add(
        DiarySearchHit(
          key: 'moment:${moment.id}:comment:${comment.id}',
          dateStr: moment.dateStr,
          updatedAt: comment.createdAt,
          sourceLabel: '评论',
          content: comment.content,
          authorId: comment.authorId,
          kind: DiarySearchHitKind.legacy,
          legacyMoment: moment,
        ),
      );
    }
  }
  return hits;
}

List<DiarySearchHit> buildSharedMomentSearchHits(
  Iterable<SharedMoment> moments,
  String keyword,
) {
  final query = keyword.toLowerCase();
  final hits = <DiarySearchHit>[];
  for (final moment in moments) {
    for (final block in moment.blocks) {
      if (block.type != SharedMomentBlockType.text ||
          !block.text.toLowerCase().contains(query)) {
        continue;
      }
      hits.add(
        DiarySearchHit(
          key: 'shared:${moment.id}:block:${block.id}',
          dateStr: moment.dateStr,
          updatedAt: block.updatedAt ?? moment.updatedAt,
          sourceLabel: '共记',
          content: block.text,
          authorId: block.authorId,
          kind: DiarySearchHitKind.shared,
          sharedMoment: moment,
        ),
      );
    }
  }
  return hits;
}

/// Deduplicates retried pages and returns a stable newest-date-first ordering.
List<DiarySearchHit> mergeDiarySearchHits(
  Iterable<DiarySearchHit> existing,
  Iterable<DiarySearchHit> incoming,
) {
  final byKey = <String, DiarySearchHit>{};
  for (final hit in existing) {
    byKey[hit.key] = hit;
  }
  for (final hit in incoming) {
    byKey[hit.key] = hit;
  }
  final result = byKey.values.toList();
  result.sort((left, right) {
    final dateOrder = right.dateStr.compareTo(left.dateStr);
    if (dateOrder != 0) return dateOrder;
    final updateOrder = right.updatedAt.compareTo(left.updatedAt);
    if (updateOrder != 0) return updateOrder;
    return left.key.compareTo(right.key);
  });
  return result;
}
