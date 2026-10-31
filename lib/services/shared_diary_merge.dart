import '../models/shared_moment.dart';

/// 只移动当前用户的图片 block；所有对方 block 的相对顺序保持不变，
/// 因而既能保存图片拖动结果，也不会触发后端的 foreign-order 保护。
List<SharedMomentBlock> applySharedImageOrder({
  required Iterable<SharedMomentBlock> blocks,
  required List<String> desiredImageIds,
  required String actorId,
}) {
  final source = List<SharedMomentBlock>.of(blocks);
  final byId = {for (final block in source) block.id: block};
  final foreignImageIds = source
      .where(
        (block) =>
            block.type == SharedMomentBlockType.image &&
            block.authorId != actorId,
      )
      .map((block) => block.id)
      .toList(growable: false);
  final actorImageIds = source
      .where(
        (block) =>
            block.type == SharedMomentBlockType.image &&
            block.authorId == actorId,
      )
      .map((block) => block.id)
      .toSet();
  final desired = desiredImageIds
      .where((id) => byId[id]?.type == SharedMomentBlockType.image)
      .toList(growable: true);
  for (final id in actorImageIds) {
    if (!desired.contains(id)) desired.add(id);
  }

  final desiredForeign = desired
      .where((id) => !actorImageIds.contains(id))
      .toList(growable: false);
  if (!_sameStringList(desiredForeign, foreignImageIds)) {
    // 防御性回退：理论上 UI 不允许拖动对方照片；若外部草稿破坏了
    // 该约束，则采用服务端认可的对方顺序，并把自己的照片正常追加。
    desired
      ..removeWhere((id) => !actorImageIds.contains(id))
      ..addAll(foreignImageIds);
  }

  final actorBuckets = List.generate(
    foreignImageIds.length + 1,
    (_) => <SharedMomentBlock>[],
  );
  var foreignCursor = 0;
  for (final id in desired) {
    final block = byId[id];
    if (block == null || block.type != SharedMomentBlockType.image) continue;
    if (block.authorId == actorId) {
      actorBuckets[foreignCursor].add(block);
    } else if (foreignCursor < foreignImageIds.length &&
        foreignImageIds[foreignCursor] == id) {
      foreignCursor++;
    }
  }

  final skeleton = source
      .where(
        (block) =>
            block.type != SharedMomentBlockType.image ||
            block.authorId != actorId,
      )
      .toList(growable: true);
  if (foreignImageIds.isEmpty) {
    final firstImage = source.indexWhere(
      (block) => block.type == SharedMomentBlockType.image,
    );
    final insertionIndex = firstImage < 0
        ? 0
        : source
              .take(firstImage)
              .where(
                (block) =>
                    block.type != SharedMomentBlockType.image ||
                    block.authorId != actorId,
              )
              .length;
    skeleton.insertAll(insertionIndex, actorBuckets.single);
    return skeleton;
  }

  final result = <SharedMomentBlock>[];
  var seenForeignImages = 0;
  for (final block in skeleton) {
    if (block.type == SharedMomentBlockType.image &&
        block.authorId != actorId) {
      result.addAll(actorBuckets[seenForeignImages]);
      result.add(block);
      seenForeignImages++;
      if (seenForeignImages == foreignImageIds.length) {
        result.addAll(actorBuckets[seenForeignImages]);
      }
    } else {
      result.add(block);
    }
  }
  return result;
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool sharedTextProjectionUnchanged(
  Iterable<SharedMomentBlock> base,
  Iterable<SharedMomentBlock> draft,
) {
  final baseText = base
      .where((block) => block.type == SharedMomentBlockType.text)
      .toList(growable: false);
  final draftText = draft
      .where((block) => block.type == SharedMomentBlockType.text)
      .toList(growable: false);
  if (baseText.length != draftText.length) return false;
  for (var index = 0; index < baseText.length; index++) {
    if (!sameSharedBlock(baseText[index], draftText[index])) return false;
  }
  return true;
}

class SharedDiaryRebaseResult {
  final List<SharedMomentBlock> blocks;
  final List<Map<String, dynamic>> splits;
  final bool hasConflicts;

  const SharedDiaryRebaseResult({
    required this.blocks,
    required this.splits,
    required this.hasConflicts,
  });
}

SharedDiaryRebaseResult rebaseSharedDraft({
  required SharedMoment base,
  required SharedMoment local,
  required SharedMoment latest,
  required String currentUserId,
  required List<Map<String, dynamic>> splits,
}) {
  final result = List<SharedMomentBlock>.of(latest.blocks);
  var hasConflicts = false;
  final acceptedSplits = <Map<String, dynamic>>[];
  final handled = <String>{};
  final baseById = {for (final block in base.blocks) block.id: block};
  final localById = {for (final block in local.blocks) block.id: block};

  for (final split in splits) {
    final sourceId = split['source_block_id']?.toString() ?? '';
    final insertedId = split['inserted_block_id']?.toString() ?? '';
    final rightId = split['right_block_id']?.toString();
    final fragmentIds = split['fragments'] is List
        ? (split['fragments'] as List).map((id) => id.toString()).toList()
        : <String>[
            if ((split['left_text']?.toString() ?? '').isNotEmpty) sourceId,
            if (insertedId.isNotEmpty) insertedId,
            if (rightId != null && rightId.isNotEmpty) rightId,
          ];
    // 即使无法重放，也不能把同一组插入误当成普通新增块再次合并。
    handled.addAll([sourceId, ...fragmentIds]);
    final baseSource = baseById[sourceId];
    final latestIndex = result.indexWhere((block) => block.id == sourceId);
    if (baseSource == null ||
        latestIndex < 0 ||
        !sameSharedBlock(baseSource, result[latestIndex])) {
      hasConflicts = true;
      continue;
    }
    final replacement = fragmentIds.map((id) => localById[id]).toList();
    if (fragmentIds.isEmpty || replacement.any((block) => block == null)) {
      hasConflicts = true;
      continue;
    }
    result.replaceRange(
      latestIndex,
      latestIndex + 1,
      replacement.cast<SharedMomentBlock>(),
    );
    acceptedSplits.add(Map<String, dynamic>.from(split));
  }

  for (final original in base.blocks) {
    if (handled.contains(original.id) || original.authorId != currentUserId) {
      continue;
    }
    final localBlock = localById[original.id];
    final latestIndex = result.indexWhere((block) => block.id == original.id);
    final latestBlock = latestIndex < 0 ? null : result[latestIndex];
    if (localBlock == null) {
      if (latestBlock != null && sameSharedBlock(latestBlock, original)) {
        result.removeAt(latestIndex);
      } else if (latestBlock != null) {
        hasConflicts = true;
      } else {
        // 原 id 消失既可能是另一端已删除，也可能是对方从 offset=0 拆分后
        // 换成了新的右段 id。文档没有持久化 lineage，不能靠相同文本或时间戳
        // 猜测并删除某个新块；保守保留最新版并明确交给二次编辑核对。
        hasConflicts = true;
      }
      continue;
    }
    if (sameSharedBlock(localBlock, original)) continue;
    if (latestBlock != null && sameSharedBlock(latestBlock, original)) {
      result[latestIndex] = localBlock;
    } else if (latestBlock == null ||
        !sameSharedBlock(latestBlock, localBlock)) {
      hasConflicts = true;
    }
  }

  for (final block in local.blocks) {
    if (handled.contains(block.id) ||
        baseById.containsKey(block.id) ||
        block.authorId != currentUserId ||
        result.any((item) => item.id == block.id)) {
      continue;
    }
    _insertUsingLocalAnchors(result, local.blocks, block);
  }

  return SharedDiaryRebaseResult(
    blocks: result,
    splits: acceptedSplits,
    hasConflicts: hasConflicts,
  );
}

void _insertUsingLocalAnchors(
  List<SharedMomentBlock> target,
  List<SharedMomentBlock> local,
  SharedMomentBlock block,
) {
  final localIndex = local.indexWhere((item) => item.id == block.id);
  for (var index = localIndex - 1; index >= 0; index--) {
    final anchor = target.indexWhere((item) => item.id == local[index].id);
    if (anchor >= 0) {
      target.insert(anchor + 1, block);
      return;
    }
  }
  for (var index = localIndex + 1; index < local.length; index++) {
    final anchor = target.indexWhere((item) => item.id == local[index].id);
    if (anchor >= 0) {
      target.insert(anchor, block);
      return;
    }
  }
  target.add(block);
}

bool sameSharedBlock(SharedMomentBlock a, SharedMomentBlock b) =>
    a.id == b.id &&
    a.type == b.type &&
    a.authorId == b.authorId &&
    a.text == b.text &&
    a.imageUrl == b.imageUrl;
