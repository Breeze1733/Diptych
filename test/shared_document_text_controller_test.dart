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
    expect(
      splits.single['fragments'],
      blocks.map((block) => block.id).toList(),
    );
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

  test(
    'several insertions in one partner passage remain independently editable',
    () {
      final source = SharedMomentBlock.text(
        id: 'partner',
        authorId: 'B',
        text: 'abcd',
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
        text: 'aXbcd',
        selection: TextSelection.collapsed(offset: 2),
      );
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.value = const TextEditingValue(
        text: 'aXbcYd',
        selection: TextSelection.collapsed(offset: 5),
      );
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.value = const TextEditingValue(
        text: 'aXbZcYd',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(blocks.map((block) => block.text), [
        'a',
        'X',
        'b',
        'Z',
        'c',
        'Y',
        'd',
      ]);
      expect(blocks.map((block) => block.authorId), [
        'B',
        'A',
        'B',
        'A',
        'B',
        'A',
        'B',
      ]);
      expect(splits, hasLength(1));
      expect(
        splits.single['fragments'],
        blocks.map((block) => block.id).toList(),
      );

      // Undo only the middle insertion, preserving the two others.
      controller.value = const TextEditingValue(
        text: 'aXbcYd',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(blocks.map((block) => block.text), ['a', 'X', 'bc', 'Y', 'd']);
      expect(
        splits.single['fragments'],
        blocks.map((block) => block.id).toList(),
      );

      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 5,
      );
      controller.value = const TextEditingValue(
        text: 'aXbcd',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(blocks.map((block) => block.text), ['a', 'X', 'bcd']);
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 2,
      );
      controller.value = const TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(splits, isEmpty);
      expect(blocks, hasLength(1));
      expect(blocks.single.id, 'partner');
      expect(blocks.single.text, 'abcd');
    },
  );

  test('different partner passages each retain their own split group', () {
    final first = SharedMomentBlock.text(id: 'b1', authorId: 'B', text: 'ab');
    final second = SharedMomentBlock.text(id: 'b2', authorId: 'B', text: 'cd');
    final blocks = <SharedMomentBlock>[first, second];
    final splits = <Map<String, dynamic>>[];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [first, second],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.value = const TextEditingValue(
      text: 'aXbcd',
      selection: TextSelection.collapsed(offset: 2),
    );
    controller.selection = const TextSelection.collapsed(offset: 4);
    controller.value = const TextEditingValue(
      text: 'aXbcYd',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(splits.map((item) => item['source_block_id']), ['b1', 'b2']);
    expect(blocks.map((block) => block.text), ['a', 'X', 'b', 'c', 'Y', 'd']);
  });

  test('repeated characters are inserted at the actual caret', () {
    final source = SharedMomentBlock.text(id: 'b', authorId: 'B', text: 'aaa');
    final blocks = <SharedMomentBlock>[source];
    final splits = <Map<String, dynamic>>[];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [source],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.value = const TextEditingValue(
      text: 'aaaa',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(blocks.map((block) => block.text), ['a', 'a', 'aa']);
    expect(blocks.map((block) => block.authorId), ['B', 'A', 'B']);
    controller.value = const TextEditingValue(
      text: 'aaa',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(splits, isEmpty);
    expect(blocks.single.text, 'aaa');
  });

  test('IME composing replacement remains in the inserted author run', () {
    final source = SharedMomentBlock.text(id: 'b', authorId: 'B', text: '甲乙');
    final blocks = <SharedMomentBlock>[source];
    final splits = <Map<String, dynamic>>[];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [source],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.value = const TextEditingValue(
      text: '甲z乙',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 1, end: 2),
    );
    controller.value = const TextEditingValue(
      text: '甲中文乙',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 1, end: 3),
    );
    expect(controller.text, '甲中文乙');
    expect(blocks.map((block) => block.text), ['甲', '中文', '乙']);
    expect(
      splits.single['fragments'],
      blocks.map((block) => block.id).toList(),
    );
  });

  test('legacy split at offset zero is upgraded without losing text', () {
    final source = SharedMomentBlock.text(id: 'b', authorId: 'B', text: '原文');
    final blocks = <SharedMomentBlock>[
      SharedMomentBlock.text(id: 'a', authorId: 'A', text: '插入'),
      SharedMomentBlock.text(id: 'right', authorId: 'B', text: '原文'),
    ];
    final splits = <Map<String, dynamic>>[
      {
        'source_block_id': 'b',
        'left_text': '',
        'inserted_block_id': 'a',
        'right_block_id': 'right',
        'right_text': '原文',
      },
    ];
    final controller = SharedDocumentTextController(
      blocks: blocks,
      baseBlocks: [source],
      splitForeignText: splits,
      currentUserId: 'A',
    );
    addTearDown(controller.dispose);
    expect(controller.text, '插入原文');
    expect(blocks.map((block) => block.id), ['a', 'b']);
    expect(splits.single['fragments'], ['a', 'b']);
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.value = const TextEditingValue(
      text: '插入原新文',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(blocks.map((block) => block.text), ['插入', '原', '新', '文']);
    expect(
      splits.single['fragments'],
      blocks.map((block) => block.id).toList(),
    );
  });

  test('emoji and a standalone newline retain their authors and positions', () {
    final source = SharedMomentBlock.text(
      id: 'b',
      authorId: 'B',
      text: '😀散步🌷',
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
    controller.selection = const TextSelection.collapsed(offset: 2);
    controller.value = const TextEditingValue(
      text: '😀\n散步🌷',
      selection: TextSelection.collapsed(offset: 3),
    );
    controller.selection = const TextSelection.collapsed(offset: 5);
    controller.value = const TextEditingValue(
      text: '😀\n散步💕🌷',
      selection: TextSelection.collapsed(offset: 7),
    );
    expect(blocks.map((block) => block.text), ['😀', '\n', '散步', '💕', '🌷']);
    expect(blocks.map((block) => block.authorId), ['B', 'A', 'B', 'A', 'B']);
    expect(
      splits.single['fragments'],
      blocks.map((block) => block.id).toList(),
    );
  });
}
