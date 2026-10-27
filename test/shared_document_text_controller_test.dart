import 'package:diptych/controllers/shared_document_text_controller.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edits own text as part of one continuous document', () {
    final blocks = <SharedMomentBlock>[
      SharedMomentBlock.text(id: 'a', authorId: 'A', text: '第一段\n'),
      SharedMomentBlock.text(id: 'b', authorId: 'B', text: '第二段'),
    ];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: List.of(blocks),
      splitForeignText: [],
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: '第一段。\n第二段',
      selection: TextSelection.collapsed(offset: 4),
    );

    expect(controller.text, '第一段。\n第二段');
    expect(blocks.first.text, '第一段。\n');
    expect(blocks.first.authorId, 'A');
  });

  test(
    'rejects deleting partner text without splitting the visible editor',
    () {
      String? rejection;
      final blocks = <SharedMomentBlock>[
        SharedMomentBlock.text(id: 'a', authorId: 'A', text: '我的'),
        SharedMomentBlock.text(id: 'b', authorId: 'B', text: '你的'),
      ];
      final controller = SharedDocumentTextController(
        blocks: blocks,
        baseBlocks: List.of(blocks),
        splitForeignText: [],
        currentUserId: 'A',
        onEditRejected: (message) => rejection = message,
      );
      addTearDown(controller.dispose);

      controller.value = const TextEditingValue(
        text: '我的的',
        selection: TextSelection.collapsed(offset: 2),
      );

      expect(controller.text, '我的你的');
      expect(blocks[1].text, '你的');
      expect(rejection, contains('对方文字受保护'));
    },
  );

  test('typing inside partner text creates an atomic backend split', () {
    final source = SharedMomentBlock.text(
      id: 'partner',
      authorId: 'B',
      text: '上午散步',
    );
    final blocks = <SharedMomentBlock>[source];
    final splits = <Map<String, dynamic>>[];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [source],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: '上午一起去散步',
      selection: TextSelection.collapsed(offset: 5),
    );

    expect(controller.text, '上午一起去散步');
    expect(blocks.map((block) => block.authorId), ['B', 'A', 'B']);
    expect(blocks.map((block) => block.text), ['上午', '一起去', '散步']);
    expect(splits, hasLength(1));
    expect(splits.single['source_block_id'], 'partner');
    expect(splits.single['inserted_block_id'], blocks[1].id);
    expect(splits.single['right_block_id'], blocks[2].id);
  });

  test('removing a pending insertion restores the original partner block', () {
    final source = SharedMomentBlock.text(
      id: 'partner',
      authorId: 'B',
      text: '上午散步',
    );
    final blocks = <SharedMomentBlock>[source];
    final splits = <Map<String, dynamic>>[];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [source],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: '上午一起去散步',
      selection: TextSelection.collapsed(offset: 5),
    );

    controller.value = const TextEditingValue(
      text: '上午散步',
      selection: TextSelection.collapsed(offset: 2),
    );

    expect(splits, isEmpty);
    expect(blocks, hasLength(1));
    expect(blocks.single.id, source.id);
    expect(blocks.single.text, source.text);
  });
}
