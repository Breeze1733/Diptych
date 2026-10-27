import 'package:diptych/models/moment.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/utils/diary_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy and shared hits merge in stable date order without duplicates',
    () {
      final older = DateTime(2025, 6, 17, 9);
      final newer = DateTime(2025, 6, 18, 10);
      final legacy = Moment(
        id: 'legacy-1',
        dateStr: '2025-06-17',
        authorId: 'A',
        feeling: '一起散步',
        comments: [
          Comment(
            id: 'comment-1',
            authorId: 'B',
            content: '下次一起去',
            createdAt: older.add(const Duration(hours: 1)),
          ),
        ],
        createdAt: older,
        updatedAt: older,
      );
      final shared = SharedMoment(
        id: 'shared-1',
        dateStr: '2025-06-18',
        revision: 2,
        blocks: [
          SharedMomentBlock.text(
            id: 'block-1',
            authorId: 'B',
            text: '今天一起看海',
            updatedAt: newer,
          ),
          SharedMomentBlock.image(
            id: 'image-1',
            authorId: 'A',
            imageUrl: 'https://images.invalid/ignored.jpg',
          ),
        ],
        createdAt: newer,
        updatedAt: newer,
      );

      final sharedHits = buildSharedMomentSearchHits([shared], '一起');
      final legacyHits = buildLegacyMomentSearchHits([legacy], '一起');
      final merged = mergeDiarySearchHits(
        [...legacyHits, ...sharedHits],
        [...sharedHits, ...legacyHits],
      );

      expect(sharedHits, hasLength(1));
      expect(sharedHits.single.sourceLabel, '共记');
      expect(sharedHits.single.authorId, 'B');
      expect(sharedHits.single.kind, DiarySearchHitKind.shared);
      expect(sharedHits.single.sharedMoment?.id, 'shared-1');
      expect(
        legacyHits.every((hit) => hit.legacyMoment?.id == 'legacy-1'),
        isTrue,
      );
      expect(merged, hasLength(3));
      expect(merged.first.dateStr, '2025-06-18');
      expect(merged.map((hit) => hit.key).toSet(), hasLength(3));
    },
  );
}
