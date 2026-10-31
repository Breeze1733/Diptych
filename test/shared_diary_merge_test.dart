import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/services/shared_diary_merge.dart';
import 'package:flutter_test/flutter_test.dart';

SharedMoment _day(List<SharedMomentBlock> blocks) => SharedMoment(
  id: 'day',
  dateStr: '2026-10-31',
  revision: 1,
  blocks: blocks,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
SharedMomentBlock _text(String id, String author, String text) =>
    SharedMomentBlock.text(id: id, authorId: author, text: text);
SharedMomentBlock _image(String id, String author) => SharedMomentBlock.image(
  id: id,
  authorId: author,
  imageUrl: 'https://images.invalid/$id.jpg',
);

void main() {
  test(
    'reordering own images preserves all foreign text and image anchors',
    () {
      final blocks = [
        _text('t1', 'B', '前'),
        _image('a1', 'A'),
        _image('b1', 'B'),
        _text('t2', 'B', '后'),
        _image('a2', 'A'),
        _image('b2', 'B'),
      ];
      final sorted = applySharedImageOrder(
        blocks: blocks,
        desiredImageIds: ['a2', 'b1', 'a1', 'b2'],
        actorId: 'A',
      );
      expect(
        sorted
            .where((b) => b.type == SharedMomentBlockType.image)
            .map((b) => b.id),
        ['a2', 'b1', 'a1', 'b2'],
      );
      expect(sorted.where((b) => b.authorId == 'B').map((b) => b.id), [
        't1',
        'b1',
        't2',
        'b2',
      ]);
    },
  );

  test('invalid foreign image order falls back without dropping any image', () {
    final sorted = applySharedImageOrder(
      blocks: [_image('a', 'A'), _image('b1', 'B'), _image('b2', 'B')],
      desiredImageIds: ['b2', 'a', 'b1'],
      actorId: 'A',
    );
    expect(sorted.map((b) => b.id), ['a', 'b1', 'b2']);
  });

  test(
    'independent edits merge with new local blocks anchored to the document',
    () {
      final own = _text('own', 'A', '原文'),
          foreign = _text('foreign', 'B', '对方');
      final base = _day([own, foreign]);
      final result = rebaseSharedDraft(
        base: base,
        local: _day([
          own.copyWith(text: '修改'),
          _text('insert', 'A', '插入'),
          foreign,
        ]),
        latest: _day([own, foreign.copyWith(text: '对方更新')]),
        currentUserId: 'A',
        splits: [],
      );
      expect(result.hasConflicts, isFalse);
      expect(result.blocks.map((b) => b.text), ['修改', '插入', '对方更新']);
    },
  );

  test('replaying a foreign split keeps its fragments contiguous and preserves its metadata', () {
    final source = _text('source', 'B', '前后');
    final split = <String, dynamic>{
      'source_block_id': 'source',
      'fragments': ['source', 'insert', 'right'],
    };
    final result = rebaseSharedDraft(
      base: _day([source]),
      local: _day([
        source.copyWith(text: '前'),
        _text('insert', 'A', '中'),
        _text('right', 'B', '后'),
      ]),
      latest: _day([source, _text('new', 'B', '新')]),
      currentUserId: 'A',
      splits: [split],
    );
    expect(result.hasConflicts, isFalse);
    expect(result.blocks.map((b) => b.text), ['前', '中', '后', '新']);
    expect(result.splits, [split]);
  });

  test('a changed split source reports conflict without duplicating its unaccepted insert', () {
    final source = _text('source', 'B', '前后');
    final latest = source.copyWith(text: '远端改写');
    final result = rebaseSharedDraft(
      base: _day([source]),
      local: _day([
        source.copyWith(text: '前'),
        _text('insert', 'A', '中'),
        _text('right', 'B', '后'),
      ]),
      latest: _day([latest]),
      currentUserId: 'A',
      splits: [
        {
          'source_block_id': 'source',
          'fragments': ['source', 'insert', 'right'],
        },
      ],
    );
    expect(result.hasConflicts, isTrue);
    expect(result.blocks, [latest]);
    expect(result.splits, isEmpty);
  });

  test(
    'disappearing block ids never cause text-based guesses about split lineage',
    () {
      final original = _text('original', 'A', '原文');
      final latest = [_text('insert', 'B', '对方插入'), _text('right', 'A', '原文')];
      final result = rebaseSharedDraft(
        base: _day([original]),
        local: _day([]),
        latest: _day(latest),
        currentUserId: 'A',
        splits: [],
      );
      expect(result.hasConflicts, isTrue);
      expect(result.blocks, latest);
    },
  );

  test(
    'text-only conflict detection ignores photos but detects changed text',
    () {
      final own = _text('own', 'A', '原文');
      expect(
        sharedTextProjectionUnchanged(
          [own, _image('a', 'A')],
          [_image('b', 'B'), own],
        ),
        isTrue,
      );
      expect(
        sharedTextProjectionUnchanged([own], [own.copyWith(text: '新文')]),
        isFalse,
      );
    },
  );
}
