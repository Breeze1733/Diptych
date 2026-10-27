import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../controllers/moment_upload_controller.dart';
import '../models/shared_moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/private_image_cache.dart';
import '../widgets/image_gallery.dart';
import '../widgets/photo_grid_picker.dart';
import '../widgets/shared_diary_document.dart';

class SharedDiaryEditorScreen extends ConsumerStatefulWidget {
  final SharedMoment initialMoment;
  final List<SharedMomentBlock>? initialBlocks;
  final List<Map<String, dynamic>> initialSplitForeignText;
  final SharedMoment? conflictReference;

  const SharedDiaryEditorScreen({
    super.key,
    required this.initialMoment,
    this.initialBlocks,
    this.initialSplitForeignText = const [],
    this.conflictReference,
  });

  @override
  ConsumerState<SharedDiaryEditorScreen> createState() =>
      _SharedDiaryEditorScreenState();
}

class _SharedDiaryEditorScreenState
    extends ConsumerState<SharedDiaryEditorScreen> {
  late final String _userId;
  late final SharedMoment _baseMoment;
  late final List<SharedMomentBlock> _blocks;
  late final List<Map<String, dynamic>> _splitForeignText;
  late final MomentUploadController _uploads;
  final Map<String, TextEditingController> _textControllers = {};
  final List<PhotoEntry> _photos = [];
  final List<_SharedPhotoMeta> _photoMetas = [];
  bool _saving = false;
  bool _savedSuccessfully = false;
  bool _exitDialogOpen = false;

  Map<String, String> get _uploadedUrls => _uploads.uploadedUrls;
  Map<String, PhotoUploadStatus> get _uploadStatuses => _uploads.statuses;
  Map<String, double> get _uploadProgress => _uploads.progress;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('未登录');
    _userId = user.uid;
    _baseMoment = widget.initialMoment;
    _blocks = List<SharedMomentBlock>.of(
      widget.initialBlocks ?? widget.initialMoment.blocks,
    );
    _splitForeignText = widget.initialSplitForeignText
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    for (final block in _blocks) {
      if (block.type == SharedMomentBlockType.text) {
        if (block.authorId == _userId) {
          _textControllers[block.id] = TextEditingController(text: block.text);
        }
      } else {
        _photos.add(PhotoEntry.url(block.imageUrl));
        _photoMetas.add(
          _SharedPhotoMeta(blockId: block.id, authorId: block.authorId),
        );
      }
    }
    _uploads = MomentUploadController(
      storage: ref.read(storageServiceProvider),
      folder: 'shared_${_baseMoment.dateStr}_$_userId',
      photos: () => _photos,
      onUploaded: () {
        if (mounted) setState(() {});
      },
      committedUrls: _baseMoment.blocks
          .where((block) => block.type == SharedMomentBlockType.image)
          .map((block) => block.imageUrl),
    )..addListener(_onUploadsChanged);
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _uploads
      ..removeListener(_onUploadsChanged)
      ..dispose();
    super.dispose();
  }

  void _insertOwnText(int blockIndex) {
    if (_isPendingSplitBoundary(blockIndex)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先保存当前拆分，再在这两段之间继续添加')));
      return;
    }
    final block = SharedMomentBlock.text(authorId: _userId, text: '');
    setState(() {
      _blocks.insert(blockIndex.clamp(0, _blocks.length), block);
      _textControllers[block.id] = TextEditingController();
    });
  }

  bool _isSplitInsertion(String blockId) =>
      _splitForeignText.any((item) => item['inserted_block_id'] == blockId);

  /// 后端要求一次尚未保存的“左段 / 我的插入 / 右段”原子且连续。
  /// 通用插入按钮不能出现在这个序列内部，否则会产生永远无法提交的草稿。
  bool _isPendingSplitBoundary(int insertionIndex) {
    if (insertionIndex <= 0 || insertionIndex >= _blocks.length) return false;
    final beforeId = _blocks[insertionIndex - 1].id;
    final afterId = _blocks[insertionIndex].id;
    for (final split in _splitForeignText) {
      final sequence = <String>[
        if ((split['left_text']?.toString() ?? '').isNotEmpty)
          split['source_block_id']?.toString() ?? '',
        split['inserted_block_id']?.toString() ?? '',
        if ((split['right_text']?.toString() ?? '').isNotEmpty)
          split['right_block_id']?.toString() ?? '',
      ].where((id) => id.isNotEmpty).toList(growable: false);
      for (var index = 1; index < sequence.length; index++) {
        if (sequence[index - 1] == beforeId && sequence[index] == afterId) {
          return true;
        }
      }
    }
    return false;
  }

  void _deleteOwnText(SharedMomentBlock block) {
    if (_isSplitInsertion(block.id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('拆分插入的段落请先保存；若要撤销，可退出且不保存')));
      return;
    }
    setState(() {
      _blocks.removeWhere((item) => item.id == block.id);
      _textControllers.remove(block.id)?.dispose();
    });
  }

  Future<void> _insertInsideForeignText(SharedMomentBlock block) async {
    final alreadySplit = _splitForeignText.any(
      (item) =>
          item['source_block_id'] == block.id ||
          item['right_block_id'] == block.id,
    );
    final belongsToBase = _baseMoment.blocks.any((item) => item.id == block.id);
    if (alreadySplit || !belongsToBase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同一原段一次保存只能拆分一次，请先保存后再继续插入')),
      );
      return;
    }
    final insertion = await showDialog<_SplitInsertion>(
      context: context,
      builder: (_) => _SplitTextDialog(block: block),
    );
    if (insertion == null || !mounted) return;
    final index = _blocks.indexWhere((item) => item.id == block.id);
    if (index < 0) return;
    final offset = insertion.offset.clamp(0, block.text.length);
    final left = block.text.substring(0, offset);
    final right = block.text.substring(offset);
    final inserted = SharedMomentBlock.text(
      authorId: _userId,
      text: insertion.text,
    );
    final rightBlock = right.isEmpty
        ? null
        : SharedMomentBlock.text(authorId: block.authorId, text: right);
    final replacement = <SharedMomentBlock>[
      if (left.isNotEmpty) block.copyWith(text: left),
      inserted,
      ?rightBlock,
    ];
    setState(() {
      _blocks.replaceRange(index, index + 1, replacement);
      _textControllers[inserted.id] = TextEditingController(
        text: insertion.text,
      );
      _splitForeignText.add({
        'source_block_id': block.id,
        'left_text': left,
        'inserted_block_id': inserted.id,
        'right_block_id': rightBlock?.id,
        'right_text': right,
      });
    });
  }

  void _addPhotos(List<PhotoEntry> entries) {
    if (entries.isEmpty) return;
    setState(() {
      for (final entry in entries) {
        final block = SharedMomentBlock.image(authorId: _userId, imageUrl: '');
        _photos.add(entry);
        _photoMetas.add(_SharedPhotoMeta(blockId: block.id, authorId: _userId));
        _blocks.add(block);
      }
    });
    _uploads.enqueue(entries);
  }

  void _removePhoto(int index) {
    if (index < 0 || index >= _photos.length) return;
    if (_photoMetas[index].authorId != _userId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('只能移除自己加入的照片')));
      return;
    }
    setState(() {
      final entry = _photos.removeAt(index);
      final meta = _photoMetas.removeAt(index);
      _blocks.removeWhere((block) => block.id == meta.blockId);
      _uploads.remove(entry);
    });
  }

  void _retryPhoto(int index) {
    if (index >= 0 && index < _photos.length) {
      _uploads.enqueue([_photos[index]]);
    }
  }

  Future<List<SharedMomentBlock>> _resolveBlocks() async {
    await _uploads.prepareForPublish();
    final imageUrlsById = <String, String>{};
    for (var index = 0; index < _photos.length; index++) {
      final entry = _photos[index];
      final url = entry.isLocal ? _uploadedUrls[entry.file!.path] : entry.url;
      if (url == null || url.isEmpty) {
        throw StateError('部分照片尚未上传完成，请重试');
      }
      imageUrlsById[_photoMetas[index].blockId] = url;
    }

    final result = <SharedMomentBlock>[];
    for (final block in _blocks) {
      if (block.type == SharedMomentBlockType.image) {
        final url = imageUrlsById[block.id];
        if (url != null) result.add(block.copyWith(imageUrl: url));
        continue;
      }
      if (block.authorId != _userId) {
        result.add(block);
        continue;
      }
      final text = (_textControllers[block.id]?.text ?? block.text).trim();
      if (text.isEmpty) {
        if (_isSplitInsertion(block.id)) {
          throw StateError('插入到对方段落中的文字不能为空');
        }
        continue;
      }
      result.add(block.copyWith(text: text));
    }
    return result;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    _uploads.setPublishing(true);
    try {
      final draftBlocks = await _resolveBlocks();
      if (!mounted) return;
      final saved = await ref
          .read(apiServiceProvider)
          .updateSharedMoment(
            moment: _baseMoment,
            blocks: draftBlocks,
            splitForeignText: _splitForeignText,
          );
      await _acceptSaved(saved);
    } on SharedMomentConflictException catch (error) {
      if (!mounted) return;
      final draftBlocks = await _resolveBlocks();
      if (!mounted) return;
      final localDraft = _baseMoment.copyWith(blocks: draftBlocks);
      final saved = await Navigator.of(context).push<SharedMoment>(
        MaterialPageRoute(
          builder: (_) => SharedDiaryConflictScreen(
            base: _baseMoment,
            latest: error.latest,
            localDraft: localDraft,
            currentUserId: _userId,
            splitForeignText: _splitForeignText,
          ),
        ),
      );
      if (saved != null && mounted) await _acceptSaved(saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('共记保存失败：${_friendlyError(error)}'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    } finally {
      _uploads.setPublishing(false);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptSaved(SharedMoment saved) async {
    final savedUrls = saved.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl)
        .toSet();
    final previousUrls = _baseMoment.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl);
    _uploads.setCommittedUrls(savedUrls);
    for (final url in {...previousUrls, ..._uploadedUrls.values}) {
      if (savedUrls.contains(url)) continue;
      _uploads.deleteOrphan(url);
      try {
        await PrivateImageCache().removeFile(url);
      } catch (_) {}
    }
    try {
      await CacheService.saveSharedMoment(saved.dateStr, saved);
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(sharedMomentProvider(saved.dateStr));
    await _closeWithResult(saved);
  }

  Future<void> _closeWithResult(SharedMoment saved) async {
    if (!mounted) return;
    setState(() {
      _savedSuccessfully = true;
      _saving = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, saved);
  }

  bool get _hasChanges {
    if (_savedSuccessfully) return false;
    if (_photos.any((entry) => entry.isLocal)) return true;
    final current = <SharedMomentBlock>[];
    for (final block in _blocks) {
      if (block.type == SharedMomentBlockType.text &&
          block.authorId == _userId) {
        current.add(
          block.copyWith(text: _textControllers[block.id]?.text ?? block.text),
        );
      } else {
        current.add(block);
      }
    }
    if (current.length != _baseMoment.blocks.length) return true;
    for (var index = 0; index < current.length; index++) {
      if (!_sameSharedBlock(current[index], _baseMoment.blocks[index])) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleBack() async {
    if (_saving || _exitDialogOpen || _savedSuccessfully) return;
    if (!_hasChanges) {
      setState(() => _savedSuccessfully = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
      return;
    }
    _exitDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这次共写修改？'),
        content: const Text('尚未保存的文字和照片会丢失；服务器上已经保存的共记不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (discard != true || !mounted) return;
    _uploads.cancelUploads();
    final committed = _baseMoment.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl)
        .toSet();
    for (final url in _uploadedUrls.values) {
      if (!committed.contains(url)) _uploads.deleteOrphan(url);
    }
    setState(() => _savedSuccessfully = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  String _friendlyError(Object error) {
    final value = error.toString();
    return value.startsWith('Exception: ') ? value.substring(11) : value;
  }

  @override
  Widget build(BuildContext context) {
    final localCount = _photos.where((entry) => entry.isLocal).length;
    final doneCount = _photos
        .where(
          (entry) =>
              entry.isLocal && _uploadedUrls.containsKey(entry.file!.path),
        )
        .length;
    final textEntries = <({int index, SharedMomentBlock block})>[
      for (var index = 0; index < _blocks.length; index++)
        if (_blocks[index].type == SharedMomentBlockType.text)
          (index: index, block: _blocks[index]),
    ];
    return PopScope(
      canPop: _savedSuccessfully,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _baseMoment.dateStr.replaceAll('-', '.'),
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                '共记 · 基于版本 ${_baseMoment.revision}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? (_uploads.isUploading
                            ? '上传 $doneCount/$localCount'
                            : '保存中…')
                      : '保存共记',
                ),
              ),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
            children: [
              if (widget.conflictReference != null)
                _ConflictReferenceCard(moment: widget.conflictReference!),
              const _SectionTitle(
                icon: Icons.notes_rounded,
                title: '共同文字',
                subtitle: '自己的段落可直接编辑；可在对方文字的任意光标位置插入',
              ),
              TextButton.icon(
                onPressed: () => _insertOwnText(
                  textEntries.isEmpty ? 0 : textEntries.first.index,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('在开头写一段'),
              ),
              for (final entry in textEntries) ...[
                _buildTextEditor(entry.block),
                if (!_isPendingSplitBoundary(entry.index + 1))
                  TextButton.icon(
                    onPressed: () => _insertOwnText(entry.index + 1),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('在这里接着写'),
                  ),
              ],
              const SizedBox(height: 12),
              const _SectionTitle(
                icon: Icons.photo_library_outlined,
                title: '共同照片',
                subtitle: '蓝框属于 A，粉框属于 B；只能移除自己加入的照片',
              ),
              const SizedBox(height: 10),
              PhotoGridPicker(
                entries: _photos,
                statusProvider: (entry) {
                  if (!entry.isLocal) return PhotoUploadStatus.success;
                  return _uploadStatuses[entry.file!.path] ??
                      (_uploadedUrls.containsKey(entry.file!.path)
                          ? PhotoUploadStatus.success
                          : PhotoUploadStatus.idle);
                },
                progressProvider: (entry) =>
                    entry.isLocal ? _uploadProgress[entry.file!.path] : null,
                onRetry: _retryPhoto,
                onTap: (index) => showFullScreenPreview(
                  context,
                  entries: _photos,
                  initialIndex: index,
                ),
                onAdded: _addPhotos,
                onRemoved: _removePhoto,
                onReordered: (_, _) {},
                reorderEnabled: false,
                borderColorProvider: (index) =>
                    AppTheme.sharedAuthorColor(_photoMetas[index].authorId),
                badgeLabelProvider: (index) => _photoMetas[index].authorId,
                canRemove: (index) => _photoMetas[index].authorId == _userId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextEditor(SharedMomentBlock block) {
    final color = AppTheme.sharedAuthorColor(block.authorId);
    final own = block.authorId == _userId;
    return Container(
      key: ValueKey('shared-editor-text-${block.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${block.authorId} · ${own ? '我的段落' : '对方段落'}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (own)
                IconButton(
                  onPressed: () => _deleteOwnText(block),
                  tooltip: '删除这段',
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  color: AppTheme.textSecondary,
                ),
            ],
          ),
          if (own)
            TextField(
              controller: _textControllers[block.id],
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '写下这一段…',
                fillColor: Colors.white70,
              ),
              style: TextStyle(color: color, height: 1.6),
            )
          else ...[
            SelectableText(
              block.text,
              style: TextStyle(color: color, fontSize: 15, height: 1.7),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _insertInsideForeignText(block),
                icon: const Icon(Icons.vertical_align_center_rounded, size: 17),
                label: const Text('在这段中插入'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SharedDiaryConflictScreen extends StatelessWidget {
  final SharedMoment base;
  final SharedMoment latest;
  final SharedMoment localDraft;
  final String currentUserId;
  final List<Map<String, dynamic>> splitForeignText;

  const SharedDiaryConflictScreen({
    super.key,
    required this.base,
    required this.latest,
    required this.localDraft,
    required this.currentUserId,
    required this.splitForeignText,
  });

  @override
  Widget build(BuildContext context) {
    final rebased = _rebaseSharedDraft(
      base: base,
      local: localDraft,
      latest: latest,
      currentUserId: currentUserId,
      splits: splitForeignText,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('处理同时修改')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              rebased.conflicts.isEmpty
                  ? '对方在你编辑期间也保存了内容。已把互不冲突的修改合并到最新版本，请在下一页检查后再次保存。'
                  : '发现 ${rebased.conflicts.length} 处无法自动合并的修改。下一页以服务器最新版为底稿，并保留你的未提交版本供复制和核对。',
              style: const TextStyle(height: 1.6),
            ),
          ),
          if (rebased.conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final message in rebased.conflicts)
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.accentColor,
                ),
                title: Text(message),
              ),
          ],
          const SizedBox(height: 12),
          ExpansionTile(
            initiallyExpanded: true,
            title: Text('服务器最新版 · v${latest.revision}'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [SharedDiaryDocument(moment: latest, compact: true)],
          ),
          ExpansionTile(
            title: const Text('我的未提交版本'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [SharedDiaryDocument(moment: localDraft, compact: true)],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () async {
              final saved = await Navigator.of(context).push<SharedMoment>(
                MaterialPageRoute(
                  builder: (_) => SharedDiaryEditorScreen(
                    initialMoment: latest,
                    initialBlocks: rebased.blocks,
                    initialSplitForeignText: rebased.splits,
                    conflictReference: localDraft,
                  ),
                ),
              );
              if (saved != null && context.mounted) {
                Navigator.pop(context, saved);
              }
            },
            icon: const Icon(Icons.merge_rounded),
            label: const Text('进入二次合并编辑'),
          ),
        ],
      ),
    );
  }
}

class _SplitTextDialog extends StatefulWidget {
  final SharedMomentBlock block;

  const _SplitTextDialog({required this.block});

  @override
  State<_SplitTextDialog> createState() => _SplitTextDialogState();
}

class _SplitTextDialogState extends State<_SplitTextDialog> {
  late final TextEditingController _source = TextEditingController(
    text: widget.block.text,
  )..selection = TextSelection.collapsed(offset: widget.block.text.length);
  final _insertion = TextEditingController();

  @override
  void dispose() {
    _source.dispose();
    _insertion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.sharedAuthorColor(widget.block.authorId);
    return AlertDialog(
      title: const Text('插入我的一段话'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '先在对方文字中点一下放置光标；保存时会把原段无损拆成前后两段，并在中间标记你的文字。',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _source,
              readOnly: true,
              showCursor: true,
              minLines: 3,
              maxLines: 8,
              style: TextStyle(color: color, height: 1.6),
              decoration: InputDecoration(
                labelText: '${widget.block.authorId} 的原文（点选插入位置）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _insertion,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '我要插入的文字'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final text = _insertion.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(
              context,
              _SplitInsertion(
                offset: _source.selection.extentOffset,
                text: text,
              ),
            );
          },
          child: const Text('插入'),
        ),
      ],
    );
  }
}

class _ConflictReferenceCard extends StatelessWidget {
  final SharedMoment moment;

  const _ConflictReferenceCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: AppTheme.accentSurface,
      child: ExpansionTile(
        title: const Text('我的未提交版本（核对用）'),
        subtitle: const Text('自动合并不了的文字可从这里复制'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [SharedDiaryDocument(moment: moment, compact: true)],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SharedPhotoMeta {
  final String blockId;
  final String authorId;

  const _SharedPhotoMeta({required this.blockId, required this.authorId});
}

class _SplitInsertion {
  final int offset;
  final String text;

  const _SplitInsertion({required this.offset, required this.text});
}

class _RebaseResult {
  final List<SharedMomentBlock> blocks;
  final List<Map<String, dynamic>> splits;
  final List<String> conflicts;

  const _RebaseResult({
    required this.blocks,
    required this.splits,
    required this.conflicts,
  });
}

_RebaseResult _rebaseSharedDraft({
  required SharedMoment base,
  required SharedMoment local,
  required SharedMoment latest,
  required String currentUserId,
  required List<Map<String, dynamic>> splits,
}) {
  final result = List<SharedMomentBlock>.of(latest.blocks);
  final conflicts = <String>[];
  final acceptedSplits = <Map<String, dynamic>>[];
  final handled = <String>{};
  final baseById = {for (final block in base.blocks) block.id: block};
  final localById = {for (final block in local.blocks) block.id: block};

  for (final split in splits) {
    final sourceId = split['source_block_id']?.toString() ?? '';
    final insertedId = split['inserted_block_id']?.toString() ?? '';
    final rightId = split['right_block_id']?.toString();
    final baseSource = baseById[sourceId];
    final latestIndex = result.indexWhere((block) => block.id == sourceId);
    if (baseSource == null ||
        latestIndex < 0 ||
        !_sameSharedBlock(baseSource, result[latestIndex])) {
      conflicts.add('对方修改了你准备插入的原段，请在最新版中重新选择插入位置。');
      continue;
    }
    final rightBlock = rightId == null ? null : localById[rightId];
    final replacement = <SharedMomentBlock>[
      ?localById[sourceId],
      ?localById[insertedId],
      ?rightBlock,
    ];
    if (!replacement.any((block) => block.id == insertedId)) {
      conflicts.add('一处插入文字已经不存在，请在最新版中重新填写。');
      continue;
    }
    result.replaceRange(latestIndex, latestIndex + 1, replacement);
    acceptedSplits.add(Map<String, dynamic>.from(split));
    handled.addAll([sourceId, insertedId, ?rightId]);
  }

  for (final original in base.blocks) {
    if (handled.contains(original.id) || original.authorId != currentUserId) {
      continue;
    }
    final localBlock = localById[original.id];
    final latestIndex = result.indexWhere((block) => block.id == original.id);
    final latestBlock = latestIndex < 0 ? null : result[latestIndex];
    if (localBlock == null) {
      if (latestBlock != null && _sameSharedBlock(latestBlock, original)) {
        result.removeAt(latestIndex);
      } else if (latestBlock != null) {
        conflicts.add('你删除的一段文字在另一端也被修改，已保留服务器版本。');
      } else {
        // 原 id 消失既可能是另一端已删除，也可能是对方从 offset=0 拆分后
        // 换成了新的右段 id。文档没有持久化 lineage，不能靠相同文本或时间戳
        // 猜测并删除某个新块；保守保留最新版并明确交给二次编辑核对。
        conflicts.add('你删除的一段文字在另一端已被拆分或删除，请核对服务器最新版。');
      }
      continue;
    }
    if (_sameSharedBlock(localBlock, original)) continue;
    if (latestBlock != null && _sameSharedBlock(latestBlock, original)) {
      result[latestIndex] = localBlock;
    } else if (latestBlock == null ||
        !_sameSharedBlock(latestBlock, localBlock)) {
      conflicts.add('同一段自己的内容在另一端也被修改，已保留服务器版本供核对。');
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

  return _RebaseResult(
    blocks: result,
    splits: acceptedSplits,
    conflicts: conflicts,
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

bool _sameSharedBlock(SharedMomentBlock a, SharedMomentBlock b) =>
    a.id == b.id &&
    a.type == b.type &&
    a.authorId == b.authorId &&
    a.text == b.text &&
    a.imageUrl == b.imageUrl;
