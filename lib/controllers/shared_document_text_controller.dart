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
  }) : super(text: _flatten(blocks));

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
    final change = _TextChange.between(old.text, next.text);
    final beforeBlocks = List<SharedMomentBlock>.of(blocks);
    final beforeSplits = splitForeignText
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (_touchesForeignText(change.removedStart, change.removedEnd)) {
      _reject(old, '对方文字受保护；可以复制，或把光标放在其中插入自己的内容');
      return;
    }

    _removeOwnText(change.removedStart, change.removedEnd);
    _restoreCanceledSplits();
    if (change.inserted.isNotEmpty &&
        !_insertOwnText(change.removedStart, change.inserted)) {
      blocks
        ..clear()
        ..addAll(beforeBlocks);
      splitForeignText
        ..clear()
        ..addAll(beforeSplits);
      _reject(old, '同一段对方文字一次保存只能插入一次，请先保存后继续');
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
    final alreadySplit = splitForeignText.any(
      (item) =>
          item['source_block_id'] == block.id ||
          item['right_block_id'] == block.id,
    );
    final base = _findById(baseBlocks, block.id);
    if (alreadySplit || base == null) return false;

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
    splitForeignText.add({
      'source_block_id': block.id,
      'left_text': left,
      'inserted_block_id': own.id,
      'right_block_id': rightBlock?.id,
      'right_text': right,
    });
    return true;
  }

  void _restoreCanceledSplits() {
    final canceled = <Map<String, dynamic>>[];
    for (final split in splitForeignText) {
      final insertedId = split['inserted_block_id']?.toString() ?? '';
      if (blocks.any((block) => block.id == insertedId)) continue;
      canceled.add(split);
    }
    for (final split in canceled) {
      final sourceId = split['source_block_id']?.toString() ?? '';
      final rightId = split['right_block_id']?.toString();
      final original = _findById(baseBlocks, sourceId);
      if (original == null) continue;
      final ids = {sourceId, ?rightId};
      final positions = <int>[
        for (var index = 0; index < blocks.length; index++)
          if (ids.contains(blocks[index].id)) index,
      ];
      final insertionIndex = positions.isEmpty
          ? blocks.length
          : positions.reduce((a, b) => a < b ? a : b);
      blocks.removeWhere((block) => ids.contains(block.id));
      blocks.insert(insertionIndex.clamp(0, blocks.length), original);
      splitForeignText.remove(split);
    }
  }

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

  factory _TextChange.between(String oldText, String newText) {
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
