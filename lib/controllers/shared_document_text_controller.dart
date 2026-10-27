import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';

/// 把后端的文字 blocks 投影为一个连续的可编辑文档。
///
/// block 仍然承担作者归属、权限和冲突合并；用户界面只看到一篇带蓝粉
/// 文字区间的正文。修改对方文字会被拒绝，在对方文字中输入则会转换为
/// 后端支持的 left / own / right 原子拆分。
class SharedDocumentTextController extends TextEditingController {
  final List<SharedMomentBlock> blocks;
  final List<SharedMomentBlock> baseBlocks;
  final List<Map<String, dynamic>> splitForeignText;
  final String currentUserId;
  final ValueChanged<String>? onEditRejected;

  bool _settingValue = false;

  SharedDocumentTextController({
    required this.blocks,
    required this.baseBlocks,
    required this.splitForeignText,
    required this.currentUserId,
    this.onEditRejected,
  }) : super(text: _flatten(blocks)) {
    _upgradeLegacySplits();
  }

  List<SharedMomentBlock> get textRuns => blocks
      .where((block) => block.type == SharedMomentBlockType.text)
      .toList(growable: false);

  @override
  set value(TextEditingValue next) {
    if (_settingValue || next.text == super.text) {
      super.value = next;
      return;
    }

    final old = super.value;
    final change = _TextChange.between(old, next);
    final beforeBlocks = List<SharedMomentBlock>.of(blocks);
    final beforeSplits = splitForeignText
        .map(_copySplit)
        .toList(growable: false);

    if (_touchesForeignText(change.removedStart, change.removedEnd)) {
      _reject(old, '对方文字受保护；可以复制，或把光标放在其中插入自己的内容');
      return;
    }

    _removeOwnText(change.removedStart, change.removedEnd);
    _normalizeSplits();
    if (change.inserted.isNotEmpty &&
        !_insertOwnText(change.removedStart, change.inserted)) {
      blocks
        ..clear()
        ..addAll(beforeBlocks);
      splitForeignText
        ..clear()
        ..addAll(beforeSplits);
      _reject(old, '无法安全地插入这段文字，请重试');
      return;
    }

    final resolved = _flatten(blocks);
    if (resolved != next.text) {
      blocks
        ..clear()
        ..addAll(beforeBlocks);
      splitForeignText
        ..clear()
        ..addAll(beforeSplits);
      _reject(old, '这次跨作者编辑无法安全应用，请缩小选择范围后重试');
      return;
    }

    _settingValue = true;
    super.value = next;
    _settingValue = false;
  }

  void _reject(TextEditingValue old, String message) {
    _settingValue = true;
    super.value = old.copyWith(composing: TextRange.empty);
    _settingValue = false;
    onEditRejected?.call(message);
  }

  bool _touchesForeignText(int start, int end) {
    if (start >= end) return false;
    for (final range in _ranges()) {
      if (range.block.authorId == currentUserId) continue;
      if (range.start < end && range.end > start) return true;
    }
    return false;
  }

  void _removeOwnText(int start, int end) {
    if (start >= end) return;
    final ranges = _ranges();
    for (final range in ranges.reversed) {
      if (range.end <= start || range.start >= end) continue;
      final localStart = (start - range.start).clamp(
        0,
        range.block.text.length,
      );
      final localEnd = (end - range.start).clamp(0, range.block.text.length);
      final updated = range.block.text.replaceRange(localStart, localEnd, '');
      if (updated.isEmpty) {
        blocks.removeAt(range.blockIndex);
      } else {
        blocks[range.blockIndex] = range.block.copyWith(text: updated);
      }
    }
  }

  bool _insertOwnText(int offset, String inserted) {
    final ranges = _ranges();
    if (ranges.isEmpty) {
      blocks.add(
        SharedMomentBlock.text(authorId: currentUserId, text: inserted),
      );
      return true;
    }

    for (final range in ranges) {
      if (offset <= range.start || offset >= range.end) continue;
      if (range.block.authorId == currentUserId) {
        final local = offset - range.start;
        blocks[range.blockIndex] = range.block.copyWith(
          text: range.block.text.replaceRange(local, local, inserted),
        );
        return true;
      }
      return _splitForeignRun(range, offset - range.start, inserted);
    }

    _RunRange? left;
    _RunRange? right;
    for (final range in ranges) {
      if (range.end == offset) left = range;
      if (range.start == offset) {
        right = range;
        break;
      }
    }
    if (left?.block.authorId == currentUserId) {
      final range = left!;
      blocks[range.blockIndex] = range.block.copyWith(
        text: '${range.block.text}$inserted',
      );
      return true;
    }
    if (right?.block.authorId == currentUserId) {
      final range = right!;
      blocks[range.blockIndex] = range.block.copyWith(
        text: '$inserted${range.block.text}',
      );
      return true;
    }

    final insertionIndex =
        right?.blockIndex ??
        (left == null ? blocks.length : left.blockIndex + 1);
    blocks.insert(
      insertionIndex,
      SharedMomentBlock.text(authorId: currentUserId, text: inserted),
    );
    return true;
  }

  bool _splitForeignRun(_RunRange range, int offset, String inserted) {
    final block = range.block;
    Map<String, dynamic>? group;
    for (final split in splitForeignText) {
      if (_fragmentIds(split).contains(block.id)) {
        group = split;
        break;
      }
    }
    if (group == null && _findById(baseBlocks, block.id) == null) return false;

    final left = block.text.substring(0, offset);
    final right = block.text.substring(offset);
    final own = SharedMomentBlock.text(authorId: currentUserId, text: inserted);
    final rightBlock = right.isEmpty
        ? null
        : SharedMomentBlock.text(authorId: block.authorId, text: right);
    blocks.replaceRange(range.blockIndex, range.blockIndex + 1, [
      if (left.isNotEmpty) block.copyWith(text: left),
      own,
      ?rightBlock,
    ]);
    if (group == null) {
      splitForeignText.add({
        'source_block_id': block.id,
        'fragments': [block.id, own.id, if (rightBlock != null) rightBlock.id],
      });
    } else {
      final ids = _fragmentIds(group);
      final index = ids.indexOf(block.id);
      if (index < 0) return false;
      ids.replaceRange(index, index + 1, [
        block.id,
        own.id,
        if (rightBlock != null) rightBlock.id,
      ]);
      group['fragments'] = ids;
    }
    return true;
  }

  /// Normalize old conflict drafts to the multi-fragment protocol.
  void _upgradeLegacySplits() {
    for (final split in splitForeignText) {
      if (split['fragments'] is List) continue;
      final sourceId = split['source_block_id']?.toString() ?? '';
      final insertedId = split['inserted_block_id']?.toString() ?? '';
      final rightId = split['right_block_id']?.toString();
      final leftText = split['left_text']?.toString() ?? '';
      final rightText = split['right_text']?.toString() ?? '';
      final ids = <String>[
        if (leftText.isNotEmpty) sourceId,
        insertedId,
        if (rightText.isNotEmpty && rightId != null) rightId,
      ];
      if (leftText.isEmpty && rightText.isNotEmpty && rightId != null) {
        final index = blocks.indexWhere((block) => block.id == rightId);
        if (index >= 0) {
          final original = _findById(baseBlocks, sourceId);
          blocks[index] = blocks[index].copyWith(
            id: sourceId,
            createdAt: original?.createdAt,
          );
          ids[ids.indexOf(rightId)] = sourceId;
        }
      }
      split
        ..clear()
        ..addAll({'source_block_id': sourceId, 'fragments': ids});
    }
  }

  /// Removing an insertion merges only its neighboring foreign fragments;
  /// other insertions into the same original passage remain untouched.
  void _normalizeSplits() {
    for (final split in List<Map<String, dynamic>>.of(splitForeignText)) {
      final sourceId = split['source_block_id']?.toString() ?? '';
      final original = _findById(baseBlocks, sourceId);
      if (original == null) continue;
      final ids = _fragmentIds(split)
          .where((id) => blocks.any((block) => block.id == id))
          .toList(growable: true);
      var index = 0;
      while (index + 1 < ids.length) {
        final leftIndex = blocks.indexWhere((block) => block.id == ids[index]);
        final rightIndex = blocks.indexWhere(
          (block) => block.id == ids[index + 1],
        );
        if (leftIndex >= 0 &&
            rightIndex == leftIndex + 1 &&
            blocks[leftIndex].authorId == original.authorId &&
            blocks[rightIndex].authorId == original.authorId) {
          blocks[leftIndex] = blocks[leftIndex].copyWith(
            text: blocks[leftIndex].text + blocks[rightIndex].text,
          );
          blocks.removeAt(rightIndex);
          ids.removeAt(index + 1);
        } else {
          index++;
        }
      }
      final hasInsertion = ids.any((id) {
        final block = _findById(blocks, id);
        return block != null && block.authorId == currentUserId;
      });
      if (!hasInsertion) {
        final sourceIndex = blocks.indexWhere((block) => block.id == sourceId);
        if (sourceIndex >= 0) blocks[sourceIndex] = original;
        splitForeignText.remove(split);
      } else {
        split['fragments'] = ids;
      }
    }
  }

  static List<String> _fragmentIds(Map<String, dynamic> split) =>
      (split['fragments'] as List).map((id) => id.toString()).toList();

  static Map<String, dynamic> _copySplit(Map<String, dynamic> split) => {
    ...split,
    if (split['fragments'] is List)
      'fragments': List<String>.of(_fragmentIds(split)),
  };

  List<_RunRange> _ranges() {
    final result = <_RunRange>[];
    var offset = 0;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block.type != SharedMomentBlockType.text) continue;
      result.add(
        _RunRange(
          block: block,
          blockIndex: index,
          start: offset,
          end: offset + block.text.length,
        ),
      );
      offset += block.text.length;
    }
    return result;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final composing = withComposing && value.composing.isValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    var offset = 0;
    for (final block in textRuns) {
      final runStyle = baseStyle.copyWith(
        color: AppTheme.sharedAuthorColor(block.authorId),
      );
      final start = offset;
      final end = start + block.text.length;
      final composeStart = composing.start.clamp(start, end);
      final composeEnd = composing.end.clamp(start, end);
      if (composeStart < composeEnd) {
        if (composeStart > start) {
          children.add(
            TextSpan(
              text: block.text.substring(0, composeStart - start),
              style: runStyle,
            ),
          );
        }
        children.add(
          TextSpan(
            text: block.text.substring(
              composeStart - start,
              composeEnd - start,
            ),
            style: runStyle.copyWith(decoration: TextDecoration.underline),
          ),
        );
        if (composeEnd < end) {
          children.add(
            TextSpan(
              text: block.text.substring(composeEnd - start),
              style: runStyle,
            ),
          );
        }
      } else {
        children.add(TextSpan(text: block.text, style: runStyle));
      }
      offset = end;
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static String _flatten(Iterable<SharedMomentBlock> blocks) => blocks
      .where((block) => block.type == SharedMomentBlockType.text)
      .map((block) => block.text)
      .join();

  static SharedMomentBlock? _findById(
    Iterable<SharedMomentBlock> blocks,
    String id,
  ) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }
}

class _RunRange {
  final SharedMomentBlock block;
  final int blockIndex;
  final int start;
  final int end;

  const _RunRange({
    required this.block,
    required this.blockIndex,
    required this.start,
    required this.end,
  });
}

class _TextChange {
  final int removedStart;
  final int removedEnd;
  final String inserted;

  const _TextChange({
    required this.removedStart,
    required this.removedEnd,
    required this.inserted,
  });

  factory _TextChange.between(TextEditingValue old, TextEditingValue next) {
    final oldText = old.text;
    final newText = next.text;

    _TextChange? replacing(int start, int end) {
      if (start < 0 || end < start || end > oldText.length) return null;
      final insertedLength = newText.length - (oldText.length - (end - start));
      if (insertedLength < 0 || start + insertedLength > newText.length) {
        return null;
      }
      final inserted = newText.substring(start, start + insertedLength);
      if (oldText.replaceRange(start, end, inserted) != newText) return null;
      return _TextChange(
        removedStart: start,
        removedEnd: end,
        inserted: inserted,
      );
    }

    final selection = old.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = replacing(selection.start, selection.end);
      if (selected != null) return selected;
    }
    if (selection.isValid && selection.isCollapsed) {
      final caret = selection.start;
      if (newText.length >= oldText.length) {
        final insertion = replacing(caret, caret);
        if (insertion != null) return insertion;
      } else if (next.selection.isValid && next.selection.isCollapsed) {
        final deleted = oldText.length - newText.length;
        final nextCaret = next.selection.start;
        if (nextCaret == caret - deleted) {
          final backspace = replacing(nextCaret, caret);
          if (backspace != null) return backspace;
        } else if (nextCaret == caret) {
          final forwardDelete = replacing(caret, caret + deleted);
          if (forwardDelete != null) return forwardDelete;
        }
      }
    }
    final composing = old.composing;
    if (composing.isValid && !composing.isCollapsed) {
      final composed = replacing(composing.start, composing.end);
      if (composed != null) return composed;
    }

    var prefix = 0;
    final shortest = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < shortest &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }
    return _TextChange(
      removedStart: prefix,
      removedEnd: oldText.length - suffix,
      inserted: newText.substring(prefix, newText.length - suffix),
    );
  }
}
