import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../controllers/moment_upload_controller.dart';
import '../controllers/shared_document_text_controller.dart';
import '../models/shared_moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../providers/shared_diary_draft_provider.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/draft_service.dart';
import '../services/shared_diary_draft.dart';
import '../services/private_image_cache.dart';
import '../widgets/image_gallery.dart';
import '../widgets/expandable_photo_panel.dart';
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
  late SharedMoment _baseMoment;
  late final List<SharedMomentBlock> _blocks;
  late final List<Map<String, dynamic>> _splitForeignText;
  late final MomentUploadController _uploads;
  late SharedDocumentTextController _textController;
  late final SharedDiaryDraftStore _draftStore;
  SharedMoment? _conflictLatest;
  SharedMoment? _reference;
  SharedMoment? _lastSavedMoment;
  bool _initializing = true;
  bool _savingDraft = false;
  bool _importing = false;
  bool _draftBlocked = false;
  Timer? _draftTimer;
  final _pageScroll = ScrollController();
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
    _draftStore = ref.read(
      sharedDiaryDraftStoreProvider((
        userId: _userId,
        dateStr: widget.initialMoment.dateStr,
      )),
    );
    _reference = widget.conflictReference;
    _baseMoment = widget.initialMoment;
    _blocks = List<SharedMomentBlock>.of(
      widget.initialBlocks ?? widget.initialMoment.blocks,
    );
    _splitForeignText = widget.initialSplitForeignText
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    _textController = SharedDocumentTextController(
      blocks: _blocks,
      baseBlocks: _baseMoment.blocks,
      splitForeignText: _splitForeignText,
      currentUserId: _userId,
      onEditRejected: _showProtectedEditMessage,
    )..addListener(_onTextChanged);
    for (final block in _blocks) {
      if (block.type == SharedMomentBlockType.image) {
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
        if (mounted) {
          setState(() {});
          _draftTimer?.cancel();
          _draftTimer = Timer(const Duration(milliseconds: 350), () {
            if (!_initializing &&
                !_saving &&
                !_savedSuccessfully &&
                !_draftBlocked) {
              unawaited(
                _persistDraft().catchError((Object error) {
                  if (mounted) _showSaveError(error);
                }),
              );
            }
          });
        }
      },
      committedUrls: _baseMoment.blocks
          .where((block) => block.type == SharedMomentBlockType.image)
          .map((block) => block.imageUrl),
    )..addListener(_onUploadsChanged);
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    try {
      if (widget.initialBlocks == null) {
        final draft = await _draftStore.load();
        if (!mounted) return;
        if (draft != null) {
          _photos.clear();
          _photoMetas.clear();
          for (final photo in draft.photos) {
            _photos.add(photo.entry);
            _photoMetas.add(
              _SharedPhotoMeta(
                blockId: photo.blockId,
                authorId: photo.authorId,
              ),
            );
            final item = photo.item;
            if (item.isLocal && item.uploadedUrl != null) {
              _uploads.restore(
                item.file!.path,
                item.uploadedUrl!,
                item.uploadedLive ?? false,
              );
            }
          }
          _replaceText(draft.base, draft.blocks, draft.splits);
          _reference = draft.reference;
          if (widget.initialMoment.revision != draft.base.revision) {
            _conflictLatest = widget.initialMoment;
          }
          _uploads.setCommittedUrls(_imageUrls(_baseMoment));
          _uploads.enqueue(_photos);
        }
      }
    } catch (error) {
      _draftBlocked = true;
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _replaceText(
    SharedMoment base,
    List<SharedMomentBlock> blocks,
    List<Map<String, dynamic>> splits,
  ) {
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _baseMoment = base;
    _blocks
      ..clear()
      ..addAll(blocks);
    _splitForeignText
      ..clear()
      ..addAll(splits);
    _textController = SharedDocumentTextController(
      blocks: _blocks,
      baseBlocks: base.blocks,
      splitForeignText: _splitForeignText,
      currentUserId: _userId,
      onEditRejected: _showProtectedEditMessage,
    )..addListener(_onTextChanged);
  }

  Iterable<String> _imageUrls(SharedMoment moment) => moment.blocks
      .where((b) => b.type == SharedMomentBlockType.image)
      .map((b) => b.imageUrl);

  Future<void> _persistDraft() {
    if (_draftBlocked) throw StateError('已有草稿未能完整恢复，请先检查本地存储，避免覆盖');
    _draftTimer?.cancel();
    return _draftStore.save(
      SharedDiaryDraft(
        base: _baseMoment,
        blocks: List.of(_blocks),
        splits: _splitForeignText,
        reference: _reference,
        photos: [
          for (var i = 0; i < _photos.length; i++)
            SharedDraftPhoto(
              blockId: _photoMetas[i].blockId,
              authorId: _photoMetas[i].authorId,
              item: DraftPhotoItem(
                isLocal: _photos[i].isLocal,
                file: _photos[i].file,
                url: _photos[i].url,
                isMotion: _photos[i].isMotion,
                uploadLive: _photos[i].uploadLive,
                uploadedUrl: _photos[i].isLocal
                    ? _uploadedUrls[_photos[i].file!.path]
                    : null,
                uploadedLive: _photos[i].isLocal
                    ? _uploads.uploadedIsLive[_photos[i].file!.path]
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveDraft() async {
    if (_saving || _savingDraft || _initializing || _importing) return;
    setState(() => _savingDraft = true);
    try {
      await _persistDraft();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('共记草稿已保存')));
      }
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _showProtectedEditMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _pageScroll.dispose();
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _uploads
      ..removeListener(_onUploadsChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _addPhotos(List<PhotoEntry> entries) async {
    if (entries.isEmpty) return;
    setState(() => _importing = true);
    try {
      final imported = <PhotoEntry>[];
      for (final entry in entries) {
        imported.add(
          entry.isLocal
              ? PhotoEntry.file(
                  await _draftStore.importImage(entry.file!),
                  isMotion: entry.isMotion,
                  uploadLive: entry.uploadLive,
                )
              : entry,
        );
      }
      if (!mounted) return;
      setState(() {
        for (final entry in imported) {
          final block = SharedMomentBlock.image(
            authorId: _userId,
            imageUrl: '',
          );
          _photos.add(entry);
          _photoMetas.add(
            _SharedPhotoMeta(blockId: block.id, authorId: _userId),
          );
          _blocks.add(block);
        }
      });
      await _persistDraft();
      if (mounted) _uploads.enqueue(imported);
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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

  void _reorderPhoto(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _photos.length ||
        newIndex < 0 ||
        newIndex >= _photos.length ||
        oldIndex == newIndex) {
      return;
    }
    if (_photoMetas[oldIndex].authorId != _userId) {
      _showProtectedEditMessage('只能拖动自己加入的照片；对方照片的位置会作为排序锚点保留');
      return;
    }
    setState(() {
      final photo = _photos.removeAt(oldIndex);
      final meta = _photoMetas.removeAt(oldIndex);
      _photos.insert(newIndex, photo);
      _photoMetas.insert(newIndex, meta);
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

    final resolved = <SharedMomentBlock>[];
    for (final block in _blocks) {
      if (block.type == SharedMomentBlockType.image) {
        final url = imageUrlsById[block.id];
        if (url != null) resolved.add(block.copyWith(imageUrl: url));
        continue;
      }
      if (block.text.isEmpty) {
        continue;
      }
      resolved.add(block);
    }
    return _applySharedImageOrder(
      blocks: resolved,
      desiredImageIds: _photoMetas.map((meta) => meta.blockId).toList(),
      actorId: _userId,
    );
  }

  List<SharedMomentBlock> _textOnlyBlocks() {
    // Rebase only the text projection onto the unchanged server document.
    // This keeps every committed image, even if locally removed or reordered.
    return _rebaseSharedDraft(
      base: _baseMoment,
      local: _baseMoment.copyWith(
        blocks: [
          ..._blocks.where(
            (b) => b.type == SharedMomentBlockType.text && b.text.isNotEmpty,
          ),
          ..._baseMoment.blocks.where(
            (b) => b.type == SharedMomentBlockType.image,
          ),
        ],
      ),
      latest: _baseMoment,
      currentUserId: _userId,
      splits: _splitForeignText,
    ).blocks;
  }

  Future<void> _save({bool publish = true}) async {
    if (_saving || _savingDraft || _initializing || _importing) return;
    setState(() => _saving = true);
    if (publish) _uploads.setPublishing(true);
    late final List<SharedMomentBlock> draftBlocks;
    try {
      await _persistDraft();
      draftBlocks = publish ? await _resolveBlocks() : _textOnlyBlocks();
      if (!mounted) return;
      final saved = await ref
          .read(apiServiceProvider)
          .updateSharedMoment(
            moment: _baseMoment,
            blocks: draftBlocks,
            splitForeignText: _splitForeignText,
          );
      await _acceptSaved(saved, publish: publish);
    } on SharedMomentConflictException catch (error) {
      if (!mounted) return;
      var latest = error.latest;
      if (publish &&
          _textProjectionUnchanged(_baseMoment.blocks, draftBlocks) &&
          _splitForeignText.isEmpty) {
        final rebased = _rebaseSharedDraft(
          base: _baseMoment,
          local: _baseMoment.copyWith(blocks: draftBlocks),
          latest: latest,
          currentUserId: _userId,
          splits: const [],
        );
        if (rebased.conflicts.isEmpty) {
          final desiredImageIds = draftBlocks
              .where((block) => block.type == SharedMomentBlockType.image)
              .map((block) => block.id)
              .toList(growable: true);
          for (final block in latest.blocks) {
            if (block.type == SharedMomentBlockType.image &&
                !desiredImageIds.contains(block.id)) {
              // 图片不需要人工解决并发冲突：另一端新加入的照片自然追加。
              desiredImageIds.add(block.id);
            }
          }
          final merged = _applySharedImageOrder(
            blocks: rebased.blocks,
            desiredImageIds: desiredImageIds,
            actorId: _userId,
          );
          try {
            final saved = await ref
                .read(apiServiceProvider)
                .updateSharedMoment(moment: latest, blocks: merged);
            await _acceptSaved(saved, publish: true);
            return;
          } on SharedMomentConflictException catch (next) {
            latest = next.latest;
          } catch (error) {
            if (mounted) _showSaveError(error);
            return;
          }
        }
      }
      if (!mounted) return;
      setState(() => _conflictLatest = latest);
      if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对方已更新共记，请拉取最新内容后继续编辑；照片草稿已保留')),
      );
    } catch (error) {
      if (!mounted) return;
      _showSaveError(error);
    } finally {
      _uploads.setPublishing(false);
      if (mounted) setState(() => _saving = false);
    }
  }

  void _adoptDocument(
    SharedMoment latest,
    List<SharedMomentBlock> nextBlocks,
    List<Map<String, dynamic>> splits,
  ) {
    final oldImageIds = _baseMoment.blocks
        .where((b) => b.type == SharedMomentBlockType.image)
        .map((b) => b.id)
        .toSet();
    final latestImages = {
      for (final b in latest.blocks.where(
        (b) => b.type == SharedMomentBlockType.image,
      ))
        b.id: b,
    };
    final localImages = {
      for (final b in _blocks.where(
        (b) => b.type == SharedMomentBlockType.image,
      ))
        b.id: b,
    };
    for (var i = _photoMetas.length - 1; i >= 0; i--) {
      final id = _photoMetas[i].blockId;
      if (oldImageIds.contains(id) && !latestImages.containsKey(id)) {
        _photoMetas.removeAt(i);
        _photos.removeAt(i);
      } else if (!_photos[i].isLocal && latestImages.containsKey(id)) {
        _photos[i] = PhotoEntry.url(latestImages[id]!.imageUrl);
      }
    }
    for (final image in latestImages.values) {
      if (!oldImageIds.contains(image.id) &&
          !_photoMetas.any((m) => m.blockId == image.id)) {
        _photoMetas.add(
          _SharedPhotoMeta(blockId: image.id, authorId: image.authorId),
        );
        _photos.add(PhotoEntry.url(image.imageUrl));
      }
    }
    final wanted = _photoMetas.map((m) => m.blockId).toSet();
    final combined = nextBlocks
        .where(
          (b) => b.type == SharedMomentBlockType.text || wanted.contains(b.id),
        )
        .toList();
    for (final id in wanted) {
      if (!combined.any((b) => b.id == id)) {
        combined.add(latestImages[id] ?? localImages[id]!);
      }
    }
    _replaceText(latest, combined, splits);
    _uploads.setCommittedUrls(_imageUrls(latest));
    _conflictLatest = null;
  }

  Future<void> _refreshLatest() async {
    if (_saving || _initializing || _savingDraft || _importing) return;
    setState(() => _saving = true);
    try {
      await _persistDraft();
      final latest = await ref
          .read(apiServiceProvider)
          .getSharedMomentById(_baseMoment.id);
      if (mounted) {
        setState(() => _conflictLatest = latest);
        if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
      }
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _mergeLatest() async {
    final latest = _conflictLatest;
    if (latest == null || _saving || _savingDraft) return;
    setState(() => _saving = true);
    try {
      await _persistDraft();
      final localDraft = _baseMoment.copyWith(blocks: List.of(_blocks));
      final rebased = _rebaseSharedDraft(
        base: _baseMoment,
        local: localDraft,
        latest: latest,
        currentUserId: _userId,
        splits: _splitForeignText,
      );
      if (!mounted) return;
      setState(() {
        _reference = rebased.conflicts.isEmpty ? null : localDraft;
        _adoptDocument(latest, rebased.blocks, rebased.splits);
      });
      await _persistDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rebased.conflicts.isEmpty
                  ? '已拉取最新内容，照片草稿已保留，请检查后保存'
                  : '部分文字需要核对，原稿已保留供复制；照片草稿仍在',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptSaved(SharedMoment saved, {required bool publish}) async {
    final savedUrls = saved.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl)
        .toSet();
    final previousUrls = _baseMoment.blocks
        .where((block) => block.type == SharedMomentBlockType.image)
        .map((block) => block.imageUrl)
        .toList();
    _uploads.setCommittedUrls(savedUrls);
    _lastSavedMoment = saved;
    if (publish) {
      for (final url in {...previousUrls, ..._uploadedUrls.values}) {
        if (savedUrls.contains(url)) continue;
        _uploads.deleteOrphan(url);
        try {
          await PrivateImageCache().removeFile(url);
        } catch (_) {}
      }
    }
    try {
      await CacheService.saveSharedMoment(saved.dateStr, saved);
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(sharedMomentProvider(saved.dateStr));
    if (!publish) {
      setState(() {
        _reference = null;
        _adoptDocument(saved, saved.blocks, const []);
      });
      await _persistDraft();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文字已更新，照片草稿已保留')));
      }
      return;
    }
    // Clear only after the server has accepted the complete document.
    _draftTimer?.cancel();
    setState(() {
      _reference = null;
      _adoptDocument(saved, saved.blocks, const []);
    });
    await _persistDraft();
    await _draftStore.clear();
    await _closeWithResult(saved);
  }

  Future<void> _closeWithResult(SharedMoment? saved) async {
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
    final current = _applySharedImageOrder(
      blocks: _blocks,
      desiredImageIds: _photoMetas.map((meta) => meta.blockId).toList(),
      actorId: _userId,
    );
    if (current.length != _baseMoment.blocks.length) return true;
    for (var index = 0; index < current.length; index++) {
      if (!_sameSharedBlock(current[index], _baseMoment.blocks[index])) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleBack() async {
    if (_saving ||
        _savingDraft ||
        _initializing ||
        _importing ||
        _exitDialogOpen ||
        _savedSuccessfully) {
      return;
    }
    if (!_hasChanges) {
      setState(() => _savedSuccessfully = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, _lastSavedMoment);
      return;
    }
    _exitDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保留这次共记修改？'),
        content: const Text('可以把文字和照片保存为草稿，下次继续编辑。已更新到远端的内容会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            style: TextButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('保存草稿并退出'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (action == null || !mounted) return;
    _draftTimer?.cancel();
    setState(() => _saving = true);
    try {
      if (action == 'save') {
        await _persistDraft();
        if (mounted) await _closeWithResult(_lastSavedMoment);
        return;
      }
      await _draftStore.clear();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showSaveError(error);
      }
      return;
    }
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
    if (mounted) Navigator.pop(context, _lastSavedMoment);
  }

  void _showSaveError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('共记保存失败：${_friendlyError(error)}'),
        backgroundColor: AppTheme.dangerColor,
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is HandshakeException ||
        error.toString().contains('HandshakeException')) {
      return '安全连接未建立，当前编辑内容仍在。请检查手机时间或切换网络后重试';
    }
    final value = error.toString();
    return value.startsWith('Exception: ') ? value.substring(11) : value;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _savingDraft || _initializing || _importing;
    final localCount = _photos.where((entry) => entry.isLocal).length;
    final doneCount = _photos
        .where(
          (entry) =>
              entry.isLocal && _uploadedUrls.containsKey(entry.file!.path),
        )
        .length;
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
              const Text(
                '共记',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '拉取最新共记',
              onPressed: busy ? null : _refreshLatest,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_conflictLatest != null)
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '有最新共记，照片草稿已保留',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : _mergeLatest,
                        child: const Text('拉取最新并二次编辑'),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : _saveDraft,
                        child: const Text('存草稿'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => _save(publish: false),
                        child: const Text('更新文字'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => _save(),
                        child: Text(
                          _saving && _uploads.isUploading
                              ? '$doneCount/$localCount'
                              : '上传发布',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: _initializing
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: _pageScroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                  children: [
                    if (_reference != null)
                      _ConflictReferenceCard(moment: _reference!),
                    const _SectionTitle(
                      icon: Icons.photo_library_outlined,
                      title: '共同照片',
                      subtitle: '长按自己的照片可拖动排序',
                    ),
                    const SizedBox(height: 10),
                    ExpandablePhotoPanel(
                      itemCount: _photos.length + 1,
                      minimumRows: 2,
                      builder: (context, expanded) => PhotoGridPicker(
                        entries: _photos,
                        visibleRows: expanded ? null : 2,
                        statusProvider: (entry) {
                          if (!entry.isLocal) return PhotoUploadStatus.success;
                          return _uploadStatuses[entry.file!.path] ??
                              (_uploadedUrls.containsKey(entry.file!.path)
                                  ? PhotoUploadStatus.success
                                  : PhotoUploadStatus.idle);
                        },
                        progressProvider: (entry) => entry.isLocal
                            ? _uploadProgress[entry.file!.path]
                            : null,
                        onRetry: _retryPhoto,
                        onTap: (index) => showFullScreenPreview(
                          context,
                          entries: _photos,
                          initialIndex: index,
                        ),
                        onAdded: _addPhotos,
                        onRemoved: _removePhoto,
                        onReordered: _reorderPhoto,
                        canReorder: (index) =>
                            _photoMetas[index].authorId == _userId,
                        borderColorProvider: (index) =>
                            AppTheme.sharedAuthorColor(
                              _photoMetas[index].authorId,
                            ),
                        showCoverBadge: false,
                        canRemove: (index) =>
                            _photoMetas[index].authorId == _userId,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SectionTitle(
                      icon: Icons.notes_rounded,
                      title: '共同正文',
                      subtitle: '这是一篇连续文档；对方文字不可改写，但可以在任意光标位置插入',
                    ),
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('shared-continuous-text-editor'),
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor.withValues(alpha: .78),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: TextField(
                        controller: _textController,
                        minLines: 10,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        cursorColor: AppTheme.sharedAuthorColor(_userId),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.75,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: '从这里开始共同记录…\n按回车可以自然分段',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
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
            title: const Text('服务器最新版'),
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

/// 只移动当前用户的图片 block；所有对方 block 的相对顺序保持不变，
/// 因而既能保存图片拖动结果，也不会触发后端的 foreign-order 保护。
List<SharedMomentBlock> _applySharedImageOrder({
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

bool _textProjectionUnchanged(
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
    if (!_sameSharedBlock(baseText[index], draftText[index])) return false;
  }
  return true;
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
        !_sameSharedBlock(baseSource, result[latestIndex])) {
      conflicts.add('对方修改了你准备插入的原段，请在最新版中重新选择插入位置。');
      continue;
    }
    final replacement = fragmentIds.map((id) => localById[id]).toList();
    if (fragmentIds.isEmpty || replacement.any((block) => block == null)) {
      conflicts.add('一处插入文字已经不存在，请在最新版中重新填写。');
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
