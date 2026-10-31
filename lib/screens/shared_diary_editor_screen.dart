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
import '../services/shared_diary_merge.dart';
import '../services/private_image_cache.dart';
import '../widgets/image_gallery.dart';
import '../widgets/expandable_photo_panel.dart';
import '../widgets/photo_grid_picker.dart';
import '../widgets/shared_diary_document.dart';

class SharedDiaryEditorScreen extends ConsumerStatefulWidget {
  final SharedMoment initialMoment;

  const SharedDiaryEditorScreen({super.key, required this.initialMoment});

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
  SharedDiaryDraft? _submissionSnapshot;
  SharedDiaryWorkingDraft? _recoveredWorking;
  bool _reviewingConflict = false;
  bool _conflictPublish = false;
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
    _baseMoment = widget.initialMoment;
    _blocks = List<SharedMomentBlock>.of(widget.initialMoment.blocks);
    _splitForeignText = [];
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
          _updateCommittedUrls(_baseMoment);
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
      final draft = await _draftStore.load();
      if (!mounted) return;
      if (draft != null) {
        _loadSnapshot(draft);
        // Recover the last submission state, with an unfinished conflict
        // workspace offered separately.
        final working = await _draftStore.loadWorking();
        if (!mounted) return;
        if (working != null) {
          _recoveredWorking = working;
          _conflictPublish = working.publishAfterConflict;
        }
        if (widget.initialMoment.revision > draft.base.revision) {
          _conflictLatest = widget.initialMoment;
        }
        _updateCommittedUrls(_baseMoment);
        _uploads.enqueue(_photos);
      }
    } catch (error) {
      _draftBlocked = true;
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _loadSnapshot(SharedDiaryDraft draft) {
    _photos.clear();
    _photoMetas.clear();
    for (final photo in draft.photos) {
      _photos.add(photo.entry);
      _photoMetas.add(
        _SharedPhotoMeta(blockId: photo.blockId, authorId: photo.authorId),
      );
      final item = photo.item;
      if (item.isLocal &&
          item.uploadedUrl != null &&
          !_uploadedUrls.containsKey(item.file!.path)) {
        _uploads.restore(
          item.file!.path,
          item.uploadedUrl!,
          item.uploadedLive ?? false,
        );
      }
    }
    _replaceText(draft.base, draft.blocks, draft.splits);
    _reference = draft.reference;
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
      ..addAll(
        splits.map(
          (s) => <String, dynamic>{
            ...s,
            if (s['fragments'] is List)
              'fragments': List.of(s['fragments'] as List),
          },
        ),
      );
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

  SharedDiaryDraft _snapshotDraft() => SharedDiaryDraft(
    base: _baseMoment,
    blocks: List.of(_blocks),
    splits: _splitForeignText
        .map(
          (s) => <String, dynamic>{
            ...s,
            if (s['fragments'] is List)
              'fragments': List.of(s['fragments'] as List),
          },
        )
        .toList(),
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
  );

  Future<void> _persistDraft() async {
    if (_draftBlocked) throw StateError('已有草稿未能完整恢复，请先检查本地存储，避免覆盖');
    _draftTimer?.cancel();
    final snapshot = _snapshotDraft();
    if (_reviewingConflict) {
      await _draftStore.saveWorking(
        snapshot,
        publishAfterConflict: _conflictPublish,
      );
      return;
    }
    await _draftStore.save(snapshot);
  }

  Future<void> _captureConflictDraft({required bool publish}) async {
    if (_draftBlocked) throw StateError('已有草稿未能完整恢复，已阻止覆盖');
    if (!_reviewingConflict) {
      final original = _snapshotDraft();
      await _draftStore.save(original);
      _submissionSnapshot = original;
    }
    _conflictPublish = publish;
    _updateCommittedUrls(_baseMoment);
  }

  void _updateCommittedUrls(SharedMoment latest) {
    _uploads.setCommittedUrls({
      ..._imageUrls(latest),
      if (_submissionSnapshot != null) ..._imageUrls(_submissionSnapshot!.base),
      if (_conflictLatest != null) ..._imageUrls(_conflictLatest!),
      for (final draft in [
        ?_submissionSnapshot,
        if (_recoveredWorking != null) _recoveredWorking!.draft,
      ])
        for (final photo in draft.photos) ...[
          if (!photo.item.isLocal && photo.item.url != null) photo.item.url!,
          if (photo.item.uploadedUrl != null) photo.item.uploadedUrl!,
          if (photo.item.file != null &&
              _uploadedUrls[photo.item.file!.path] != null)
            _uploadedUrls[photo.item.file!.path]!,
        ],
    });
  }

  Future<void> _returnFromConflict() async {
    setState(() => _savingDraft = true);
    try {
      // Leaving conflict editing keeps the resolved local document as the new
      // editable draft rather than reverting to the pre-conflict version.
      await _draftStore.save(_snapshotDraft());
      await _draftStore.clearWorking();
      if (mounted) {
        setState(() {
          _reviewingConflict = false;
          _submissionSnapshot = null;
          _recoveredWorking = null;
        });
      }
      _updateCommittedUrls(_baseMoment);
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) {
        setState(() {
          _savingDraft = false;
        });
      }
    }
  }

  Future<void> _resumeWorkingCopy() async {
    final recovered = _recoveredWorking;
    if (recovered == null) return;
    setState(() => _savingDraft = true);
    try {
      await _captureConflictDraft(publish: recovered.publishAfterConflict);
      if (!mounted) return;
      setState(() {
        _loadSnapshot(recovered.draft);
        _reviewingConflict = true;
        _conflictPublish = recovered.publishAfterConflict;
        _reference ??= _submissionSnapshot?.base.copyWith(
          blocks: _submissionSnapshot!.blocks,
        );
        _recoveredWorking = null;
        _conflictLatest = null;
      });
      _updateCommittedUrls(_baseMoment);
      _uploads.enqueue(_photos);
    } catch (error) {
      if (mounted) _showSaveError(error);
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_saving || _savingDraft || _initializing || _importing) return;
    setState(() => _savingDraft = true);
    try {
      await _persistDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_reviewingConflict ? '二次编辑草稿已保存' : '共记草稿已保存')),
        );
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
    return applySharedImageOrder(
      blocks: resolved,
      desiredImageIds: _photoMetas.map((meta) => meta.blockId).toList(),
      actorId: _userId,
    );
  }

  List<SharedMomentBlock> _textOnlyBlocks() {
    // Rebase only the text projection onto the unchanged server document.
    // This keeps every committed image, even if locally removed or reordered.
    return rebaseSharedDraft(
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

  Future<void> _restoreFailedSubmission(
    SharedDiaryDraft submission, {
    SharedMoment? latest,
  }) async {
    if (!mounted) return;
    setState(() {
      _loadSnapshot(submission);
      _reviewingConflict = false;
      _submissionSnapshot = null;
      _recoveredWorking = null;
      if (latest != null) _conflictLatest = latest;
    });
    _updateCommittedUrls(_baseMoment);
    try {
      // Capture any uploads that completed during the attempt, keeping the
      // exact submitted text, split metadata and photo order as the fallback.
      await _draftStore.save(_snapshotDraft());
      await _draftStore.clearWorking();
    } catch (error) {
      if (mounted) _showSaveError(error);
    }
  }

  Future<void> _save({bool publish = true}) async {
    if (_saving || _savingDraft || _initializing || _importing) return;
    if (_draftBlocked) {
      _showSaveError(StateError('已有草稿未能完整恢复，已阻止覆盖'));
      return;
    }
    // Every button press establishes a fresh fallback, including confirmation
    // after conflict editing. A successful update retires this snapshot.
    final submission = _snapshotDraft();
    _submissionSnapshot = submission;
    _conflictPublish = publish;
    setState(() => _saving = true);
    if (publish) _uploads.setPublishing(true);
    late final List<SharedMomentBlock> draftBlocks;
    SharedMoment? accepted;
    try {
      _draftTimer?.cancel();
      await _draftStore.save(submission);
      draftBlocks = publish ? await _resolveBlocks() : _textOnlyBlocks();
      if (!mounted) return;
      final saved = await ref
          .read(apiServiceProvider)
          .updateSharedMoment(
            moment: _baseMoment,
            blocks: draftBlocks,
            splitForeignText: _splitForeignText,
          );
      accepted = saved;
      await _acceptSaved(saved, publish: publish);
    } on SharedMomentConflictException catch (error) {
      if (!mounted) return;
      var latest = error.latest;
      if (publish &&
          sharedTextProjectionUnchanged(_baseMoment.blocks, draftBlocks) &&
          _splitForeignText.isEmpty) {
        final rebased = rebaseSharedDraft(
          base: _baseMoment,
          local: _baseMoment.copyWith(blocks: draftBlocks),
          latest: latest,
          currentUserId: _userId,
          splits: const [],
        );
        if (!rebased.hasConflicts) {
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
          final merged = applySharedImageOrder(
            blocks: rebased.blocks,
            desiredImageIds: desiredImageIds,
            actorId: _userId,
          );
          try {
            final saved = await ref
                .read(apiServiceProvider)
                .updateSharedMoment(moment: latest, blocks: merged);
            accepted = saved;
            await _acceptSaved(saved, publish: true);
            return;
          } on SharedMomentConflictException catch (next) {
            latest = next.latest;
          } catch (error) {
            if (mounted) {
              if (accepted == null) {
                await _restoreFailedSubmission(submission, latest: latest);
              }
              if (!mounted) return;
              if (accepted != null) {
                _showDraftSyncError(error);
              } else {
                _showSaveError(error);
              }
            }
            return;
          }
        }
      }
      if (!mounted) return;
      await _restoreFailedSubmission(submission, latest: latest);
      if (!mounted) return;
      if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对方已更新共记，请拉取最新内容后继续编辑；照片草稿已保留')),
      );
    } catch (error) {
      if (!mounted) return;
      if (accepted != null) {
        _showDraftSyncError(error);
      } else {
        await _restoreFailedSubmission(submission);
        if (mounted) _showSaveError(error);
      }
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
    _updateCommittedUrls(latest);
    _conflictLatest = null;
  }

  Future<void> _mergeLatest() async {
    final latest = _conflictLatest;
    if (latest == null || _saving || _savingDraft) return;
    setState(() => _saving = true);
    try {
      await _captureConflictDraft(publish: _conflictPublish);
      final localDraft = _baseMoment.copyWith(blocks: List.of(_blocks));
      final rebased = rebaseSharedDraft(
        base: _baseMoment,
        local: localDraft,
        latest: latest,
        currentUserId: _userId,
        splits: _splitForeignText,
      );
      if (!mounted) return;
      setState(() {
        // Merging is temporary until the user confirms the resolved document.
        // Confirmation saves that result as the next submission's fallback.
        _reference = localDraft;
        _adoptDocument(latest, rebased.blocks, rebased.splits);
        _reviewingConflict = true;
        _recoveredWorking = null;
      });
      await _persistDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !rebased.hasConflicts
                  ? '已进入二次编辑，请检查后确认提交'
                  : '部分文字需从参考稿核对，确认提交前会保存处理后的副本',
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
    if (!mounted) return;
    setState(() {
      _submissionSnapshot = null;
      _recoveredWorking = null;
      _reviewingConflict = false;
      _reference = null;
      _adoptDocument(saved, saved.blocks, const []);
    });
    if (publish) {
      _uploads.setCommittedUrls(savedUrls);
    } else {
      _updateCommittedUrls(saved);
    }
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
      await _persistDraft();
      await _draftStore.clearWorking();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文字已更新，照片草稿已保留')));
      }
      return;
    }
    // Clear only after the server has accepted the complete document.
    _draftTimer?.cancel();
    await _persistDraft();
    try {
      await MomentDraftStore.transferToMomentCache(
        _snapshotDraft().photos.map((photo) => photo.item).toList(),
        savedUrls.toList(),
      );
    } catch (error) {
      debugPrint('共记已发布，原图缓存写入失败: $error');
    }
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
    final current = applySharedImageOrder(
      blocks: _blocks,
      desiredImageIds: _photoMetas.map((meta) => meta.blockId).toList(),
      actorId: _userId,
    );
    if (current.length != _baseMoment.blocks.length) return true;
    for (var index = 0; index < current.length; index++) {
      if (!sameSharedBlock(current[index], _baseMoment.blocks[index])) {
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
    if (_reviewingConflict) {
      await _returnFromConflict();
      return;
    }
    if (!_hasChanges) {
      setState(() => _saving = true);
      try {
        // Reverting to the server document must also replace any earlier draft.
        // Keep an unfinished conflict workspace, or an unreadable draft, intact.
        if (!_draftBlocked) await _persistDraft();
        await _closeWithResult(_lastSavedMoment);
      } catch (error) {
        if (mounted) _showSaveError(error);
      } finally {
        if (mounted && !_savedSuccessfully) {
          setState(() => _saving = false);
        }
      }
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

  void _showDraftSyncError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('内容已更新到最新版，但本地草稿处理失败：${_friendlyError(error)}')),
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
              Text(
                _reviewingConflict ? '共记 · 二次编辑' : '共记',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_recoveredWorking != null)
                  TextButton.icon(
                    onPressed: busy ? null : _resumeWorkingCopy,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('继续上次二次编辑'),
                  ),
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
                if (_reviewingConflict) ...[
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
                          onPressed: busy ? null : _returnFromConflict,
                          child: const Text('返回编辑'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () => _save(publish: _conflictPublish),
                      child: Text(_conflictPublish ? '确认上传发布' : '确认更新文字'),
                    ),
                  ),
                ] else
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
                      builder: (context, _) => PhotoGridPicker(
                        entries: _photos,
                        visibleRows: 2,
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

class _ConflictReferenceCard extends StatelessWidget {
  final SharedMoment moment;

  const _ConflictReferenceCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: AppTheme.accentSurface,
      child: ExpansionTile(
        title: const Text('本地内容（核对用）'),
        subtitle: const Text('供二次编辑核对，提交失败会恢复到本次提交前的状态'),
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
