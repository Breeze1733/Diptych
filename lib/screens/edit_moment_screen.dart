import '../services/private_image_cache.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../services/draft_service.dart';
import '../services/moment_save_service.dart';
import '../controllers/moment_upload_controller.dart';
import '../utils/date_helper.dart';
import '../utils/motion_photo_helper.dart';
import '../widgets/image_gallery.dart';

import '../widgets/photo_grid_picker.dart';

/// 发布/编辑动态页
class EditMomentScreen extends ConsumerStatefulWidget {
  final DateTime date;
  final Moment? existingMoment; // null 表示新建

  const EditMomentScreen({super.key, required this.date, this.existingMoment});

  @override
  ConsumerState<EditMomentScreen> createState() => _EditMomentScreenState();
}

class _EditMomentScreenState extends ConsumerState<EditMomentScreen> {
  final _feelingController = TextEditingController();
  final List<PhotoEntry> _photos = [];
  int? _mood;
  bool _isSaving = false;
  bool _isSavingDraft = false;

  /// 快照：记录最近一次已保存/已恢复到草稿的状态，用于判定是否有尚未存草稿的修改
  _EditorSnapshot? _lastSavedDraftSnapshot;

  /// 是否发布/保存成功，成功后退出不需要触发防手滑拦截
  bool _hasSavedSuccessfully = false;

  /// 防止多次快速点击返回弹出多个确认框
  bool _isExitDialogShowing = false;

  late final MomentDraftStore _draftStore;
  late final MomentUploadController _uploads;
  bool _isLoadingDraft = true;
  bool _isImportingPhotos = false;

  Map<String, String> get _uploadedUrls => _uploads.uploadedUrls;
  Map<String, bool> get _uploadedIsLive => _uploads.uploadedIsLive;
  Map<String, PhotoUploadStatus> get _uploadStatuses => _uploads.statuses;
  Map<String, double> get _uploadProgress => _uploads.progress;

  bool get _isEdit => widget.existingMoment != null;

  String get _dateStr => DateHelper.toDateStr(widget.date);

  List<DraftPhotoItem> _buildDraftItems() {
    final items = <DraftPhotoItem>[];
    for (final p in _photos) {
      if (p.isLocal && p.file != null) {
        final path = p.file!.path;
        items.add(
          DraftPhotoItem(
            isLocal: true,
            file: p.file,
            isMotion: p.isMotion,
            uploadLive: p.uploadLive,
            uploadedUrl: _uploadedUrls[path],
            uploadedLive: _uploadedIsLive[path],
          ),
        );
      } else if (!p.isLocal && p.url != null) {
        items.add(
          DraftPhotoItem(
            isLocal: false,
            url: p.url,
            isMotion: p.isMotion,
            uploadLive: p.uploadLive,
          ),
        );
      }
    }
    return items;
  }

  _EditorSnapshot _takeCurrentSnapshot() {
    return _EditorSnapshot(
      feeling: _feelingController.text,
      mood: _mood,
      photoKeys: [
        for (final p in _photos)
          if (p.isLocal && p.file != null)
            'local:${p.file!.path}:${p.uploadLive}'
          else if (!p.isLocal && p.url != null)
            'remote:${p.url}',
      ],
    );
  }

  bool get _hasChanges {
    if (_hasSavedSuccessfully) return false;

    // 1. 如果当前状态与最近一次保存/加载的草稿完全一致，说明没有未存草稿的新修改
    if (_lastSavedDraftSnapshot != null &&
        _lastSavedDraftSnapshot!.matches(
          _feelingController.text,
          _mood,
          _photos,
        )) {
      return false;
    }

    // 2. 如果无草稿快照（未存草稿或已清空草稿）：
    if (_isEdit) {
      final orig = widget.existingMoment!;
      if (_feelingController.text.trim() != orig.feeling.trim()) return true;
      if (_mood != orig.mood) return true;
      if (_photos.length != orig.imageUrls.length) return true;
      for (var i = 0; i < _photos.length; i++) {
        if (_photos[i].isLocal) return true;
        if (_photos[i].url != orig.imageUrls[i]) return true;
      }
      return false;
    } else {
      if (_feelingController.text.trim().isNotEmpty) return true;
      if (_mood != null) return true;
      if (_photos.isNotEmpty) return true;
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    final userId =
        ref.read(currentUserProvider)?.uid ?? ref.read(currentUserRoleProvider);
    if (userId == null) throw StateError('未登录');
    _draftStore = MomentDraftStore(userId: userId, dateStr: _dateStr);
    _uploads = MomentUploadController(
      storage: ref.read(storageServiceProvider),
      folder: 'user_$userId',
      photos: () => _photos,
      onUploaded: _syncDraftImages,
      committedUrls: widget.existingMoment?.imageUrls ?? const [],
    )..addListener(_onUploadsChanged);
    if (_isEdit) {
      _feelingController.text = widget.existingMoment!.feeling;
      _mood = widget.existingMoment!.mood;
      _photos.addAll(widget.existingMoment!.imageUrls.map(PhotoEntry.url));
    }
    _loadDraft();
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDraft() async {
    try {
      var draft = await _draftStore.load();
      if (draft == null && mounted) {
        final legacy = await _draftStore.loadLegacyForRecovery();
        if (legacy != null && mounted) {
          final recover = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('发现旧版本草稿'),
              content: const Text('这份草稿没有作者信息。确认属于自己后，可恢复到当前账号；跳过会保留原草稿。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('跳过'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('恢复到当前账号'),
                ),
              ],
            ),
          );
          if (recover == true) {
            await _draftStore.recoverLegacy(legacy);
            draft = await _draftStore.load();
          }
        }
      }
      if (draft != null && mounted) await _applyDraft(draft);
    } catch (error) {
      debugPrint('加载草稿失败: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('恢复草稿失败，原草稿已保留，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingDraft = false);
    }
  }

  Future<void> _applyDraft(DraftData draft) async {
    final loadedPhotos = <PhotoEntry>[];

    if (draft.photoItems.isNotEmpty) {
      for (final item in draft.photoItems) {
        if (!item.isLocal && item.url != null) {
          loadedPhotos.add(
            PhotoEntry.url(
              item.url!,
              isMotion: item.isMotion,
              uploadLive: item.uploadLive,
            ),
          );
        } else if (item.isLocal &&
            item.file != null &&
            await item.file!.exists()) {
          final f = await _draftStore.importImage(item.file!);
          final isMotion = await MotionPhotoHelper.isMotionPhoto(f);
          if (!mounted) return;
          final uploadLive = isMotion && item.uploadLive;
          loadedPhotos.add(
            PhotoEntry.file(
              f,
              isMotion: isMotion && uploadLive,
              uploadLive: isMotion && uploadLive,
            ),
          );
          if (item.uploadedUrl != null && item.uploadedUrl!.isNotEmpty) {
            final path = f.path;
            final wasLive = item.uploadedLive ?? false;
            if (wasLive == uploadLive) {
              _uploads.restore(path, item.uploadedUrl!, wasLive);
            } else {
              _uploads.deleteOrphan(item.uploadedUrl!);
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _feelingController.text = draft.feeling;
      _mood = draft.mood;
      _photos.clear();
      _photos.addAll(loadedPhotos);
    });

    _lastSavedDraftSnapshot = _takeCurrentSnapshot();

    // 对草稿中尚未上传成功或需要重新上传的本地图片，自动加入预上传队列
    _uploads.enqueue(_photos);
  }

  @override
  void dispose() {
    _uploads.removeListener(_onUploadsChanged);
    _uploads.dispose();
    _feelingController.dispose();
    super.dispose();
  }

  void _syncDraftImages() {
    if (_hasSavedSuccessfully || !mounted) return;
    _saveDraftInternal().catchError((Object error) {
      debugPrint('自动保存草稿失败: $error');
    });
  }

  void _handleRemovePhoto(int index) {
    final photo = _photos.removeAt(index);
    _uploads.remove(photo);
    setState(() {});
    _syncDraftImages();
  }

  /// 用户新选取照片处理：接收选图器已封装好的 PhotoEntry 列表
  Future<void> _handlePhotosAdded(List<PhotoEntry> newEntries) async {
    if (_isImportingPhotos || _isSaving) return;
    setState(() => _isImportingPhotos = true);
    try {
      final processed = <PhotoEntry>[];
      for (final entry in newEntries) {
        if (!entry.isLocal || entry.file == null) {
          processed.add(entry);
          continue;
        }
        final still = entry.isMotion && !entry.uploadLive;
        final file = still
            ? await _draftStore.createStillImage(entry.file!)
            : await _draftStore.importImage(entry.file!);
        processed.add(
          PhotoEntry.file(
            file,
            isMotion: !still && entry.isMotion,
            uploadLive: !still && entry.uploadLive,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _photos.addAll(processed));
      _syncDraftImages();
      _uploads.enqueue(processed);
    } catch (error) {
      debugPrint('导入照片失败: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存所选照片失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _isImportingPhotos = false);
    }
  }

  void _handleRetryUpload(int index) {
    if (index < 0 || index >= _photos.length) return;
    _uploads.enqueue([_photos[index]]);
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    _uploads.setPublishing(true);
    try {
      // 本地持久化失败时不继续发布，保留可恢复的完整快照。
      await _saveDraftInternal();
      if (!mounted) return;
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null || currentUser.uid != _draftStore.userId) {
        throw StateError('登录账号已改变，请重新打开编辑页');
      }
      await _uploads.prepareForPublish();
      if (!mounted) return;
      if (_photos.any(
        (p) => p.isLocal && !_uploadedUrls.containsKey(p.file!.path),
      )) {
        throw StateError('部分图片上传失败，请点击图片重试后发布');
      }
      final imageUrls = <String>[
        for (final photo in _photos)
          if (photo.isLocal)
            _uploadedUrls[photo.file!.path]!
          else if (photo.url != null)
            photo.url!,
      ];
      final result = await MomentSaveService(ref.read(apiServiceProvider)).save(
        dateStr: _dateStr,
        authorId: currentUser.uid,
        imageUrls: imageUrls,
        feeling: _feelingController.text.trim(),
        mood: _mood,
        existingMoment: widget.existingMoment,
      );
      // 远端记录确认成功后，清理被替换的旧资源。
      _hasSavedSuccessfully = true;
      _uploads.setCommittedUrls(result.imageUrls);
      for (final url in {...result.removedUrls, ..._uploadedUrls.values}) {
        if (result.imageUrls.contains(url)) continue;
        _uploads.deleteOrphan(url);
        try {
          await PrivateImageCache().removeFile(url);
        } catch (_) {}
      }
      try {
        await MomentDraftStore.transferToMomentCache(
          _buildDraftItems(),
          result.imageUrls,
        );
      } catch (error) {
        debugPrint('日记已保存，图片缓存写入失败: $error');
      }
      try {
        await _draftStore.clear();
      } catch (error) {
        debugPrint('日记已保存，清除草稿失败: $error');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.uploadSuccess),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      var draftSaved = false;
      try {
        await _saveDraftInternal();
        draftSaved = true;
      } catch (_) {}
      debugPrint('发布日记失败: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draftSaved ? '保存失败，已保存为草稿，请稍后重试' : '保存失败，草稿未能落盘，请保留页面后重试',
          ),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    } finally {
      _uploads.setPublishing(false);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveDraftInternal() async {
    if (_hasSavedSuccessfully) return;
    final snapshot = _takeCurrentSnapshot();
    await _draftStore.save(
      feeling: _feelingController.text,
      mood: _mood,
      items: _buildDraftItems(),
    );
    _lastSavedDraftSnapshot = snapshot;
  }

  Future<void> _discardDraftInternal() async {
    // 先取消上传，防止 clear 后异步上传回调重新生成草稿。
    _uploads.cancelUploads();
    for (final url in _uploadedUrls.values.toSet()) {
      _uploads.deleteOrphan(url);
    }
    await _draftStore.clear();
    _lastSavedDraftSnapshot = null;
  }

  /// 存草稿
  Future<void> _handleSaveDraft() async {
    final hasContent =
        _feelingController.text.trim().isNotEmpty ||
        _mood != null ||
        _photos.isNotEmpty;
    if (!hasContent) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入感受或添加照片后再存草稿')));
      return;
    }

    setState(() => _isSavingDraft = true);
    try {
      await _saveDraftInternal();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('草稿已保存'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    } catch (e) {
      debugPrint('保存草稿失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存草稿失败，请重试'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _handleBackPress() async {
    if (_isSaving || _isSavingDraft || _isLoadingDraft || _isImportingPhotos) {
      return;
    }
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    if (_isExitDialogShowing || !mounted) return;
    _isExitDialogShowing = true;
    try {
      final shouldPop = await _showExitConfirmDialog();
      if (shouldPop && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      _isExitDialogShowing = false;
    }
  }

  Future<bool> _showExitConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出编辑'),
        content: const Text('当前内容有未保存的更改，是否保留草稿？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerColor),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('放弃修改'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '保留草稿',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (result == null) {
      // 取消退出，留在页面
      return false;
    }

    if (result == true) {
      // 保留草稿并退出
      try {
        await _saveDraftInternal();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('草稿已保存'),
              backgroundColor: AppTheme.primaryColor,
            ),
          );
        }
      } catch (e) {
        debugPrint('退出时保存草稿失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('草稿保存失败，请重试后再退出')));
        }
        return false;
      }
      return true;
    } else {
      // 放弃修改并退出
      await _discardDraftInternal();
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localCount = _photos.where((p) => p.isLocal).length;
    final doneCount = _photos
        .where((p) => p.isLocal && _uploadedUrls.containsKey(p.file!.path))
        .length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          leadingWidth: 40,
          titleSpacing: 4,
          leading: BackButton(onPressed: _handleBackPress),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              DateHelper.toDateStr(widget.date).replaceAll('-', '.'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          actions: [
            SizedBox(
              width: 56,
              child: TextButton(
                onPressed:
                    _isSavingDraft ||
                        _isSaving ||
                        _isLoadingDraft ||
                        _isImportingPhotos
                    ? null
                    : _handleSaveDraft,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: EdgeInsets.zero,
                  foregroundColor: AppTheme.textSecondary,
                ),
                child: _isSavingDraft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('存草稿', style: TextStyle(fontSize: 13)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: SizedBox(
                width: 76,
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed:
                      _isSaving ||
                          _isSavingDraft ||
                          _isLoadingDraft ||
                          _isImportingPhotos
                      ? null
                      : _handleSave,
                  child: _isSaving
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _uploads.isUploading
                                ? '上传中 $doneCount/$localCount'
                                : '发布中…',
                            style: const TextStyle(fontSize: 12),
                          ),
                        )
                      : const Text(
                          AppStrings.saveButton,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _isSaving || _isLoadingDraft || _isImportingPhotos,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final outerPadding = constraints.maxHeight < 360 ? 8.0 : 12.0;
                final height = math.max(
                  0.0,
                  constraints.maxHeight - outerPadding * 2,
                );
                final gap = math.min(height / 12, height < 360 ? 6.0 : 8.0);
                final padding = math.min(
                  height / 18,
                  height < 240 ? 6.0 : 10.0,
                );
                final showTitles = height >= 180;
                final titleHeight =
                    MediaQuery.textScalerOf(context).scale(14) * 1.2;
                final sectionFrame =
                    padding * 2 + (showTitles ? titleHeight + 6 : 0);
                final contentBudget = math.max(
                  0.0,
                  height - sectionFrame * 3 - gap * 2,
                );
                final moodHeight = math.min(36.0, contentBudget * .35);
                final remaining = math.max(0.0, contentBudget - moodHeight);
                final gridWidth = math.max(
                  0.0,
                  math.min(constraints.maxWidth, 680) -
                      outerPadding * 2 -
                      padding * 2,
                );
                final photoHeight = math.min(
                  math.max(0.0, (gridWidth * 2 - 8) / 3),
                  remaining * .5,
                );

                Widget section(String title, String id, Widget content) =>
                    _buildEditorSection(
                      key: ValueKey(id),
                      title: title,
                      padding: padding,
                      showTitle: showTitles,
                      titleHeight: titleHeight,
                      child: content,
                    );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: EdgeInsets.all(outerPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: sectionFrame + moodHeight,
                            child: section(
                              AppStrings.feelingLabel,
                              'diary-mood-card',
                              _buildMoodSelector(),
                            ),
                          ),
                          SizedBox(height: gap),
                          SizedBox(
                            height: sectionFrame + photoHeight,
                            child: section(
                              AppStrings.photosLabel,
                              'diary-photos-card',
                              _buildPhotoGrid(),
                            ),
                          ),
                          SizedBox(height: gap),
                          Expanded(
                            child: section(
                              '今日感受',
                              'diary-feeling-card',
                              SelectionContainer.disabled(
                                child: TextField(
                                  key: const ValueKey('diary-feeling-input'),
                                  controller: _feelingController,
                                  expands: true,
                                  minLines: null,
                                  maxLines: null,
                                  textAlignVertical: TextAlignVertical.top,
                                  scrollPhysics: const ClampingScrollPhysics(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.6,
                                    color: AppTheme.textPrimary,
                                  ),
                                  contextMenuBuilder:
                                      (context, editableTextState) =>
                                          AdaptiveTextSelectionToolbar.buttonItems(
                                            anchors: editableTextState
                                                .contextMenuAnchors,
                                            buttonItems: editableTextState
                                                .contextMenuButtonItems,
                                          ),
                                  decoration: const InputDecoration(
                                    hintText: AppStrings.feelingHint,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoGrid() => PhotoGridPicker(
    visibleRows: 2,
    entries: _photos,
    statusProvider: (entry) {
      if (!entry.isLocal) return PhotoUploadStatus.success;
      return _uploadStatuses[entry.file!.path] ??
          (_uploadedUrls.containsKey(entry.file!.path)
              ? PhotoUploadStatus.success
              : PhotoUploadStatus.idle);
    },
    progressProvider: (entry) {
      if (!entry.isLocal) return null;
      return _uploadProgress[entry.file!.path];
    },
    onRetry: _handleRetryUpload,
    onTap: (index) {
      showFullScreenPreview(context, entries: _photos, initialIndex: index);
    },
    onAdded: _handlePhotosAdded,
    onRemoved: _handleRemovePhoto,
    onReordered: (oldIndex, newIndex) {
      setState(() {
        final photo = _photos.removeAt(oldIndex);
        _photos.insert(newIndex, photo);
      });
      _syncDraftImages();
    },
  );

  Widget _buildEditorSection({
    required Key key,
    required String title,
    required double padding,
    required bool showTitle,
    required double titleHeight,
    required Widget child,
  }) => Semantics(
    container: true,
    label: title,
    child: Container(
      key: key,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            SizedBox(
              height: titleHeight,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Expanded(child: child),
        ],
      ),
    ),
  );

  Widget _buildMoodSelector() => Row(
    children: List.generate(10, (i) {
      final score = i + 1;
      final selected = _mood == score;
      final color = AppTheme.moodColor(score);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Semantics(
            selected: selected,
            label: '心情 $score 分',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: AppTheme.moodGradient(score),
                  borderRadius: BorderRadius.circular(7),
                  border: selected
                      ? Border.all(color: color, width: 2)
                      : Border.all(color: color.withValues(alpha: .5)),
                ),
                child: InkWell(
                  onTap: () => setState(() => _mood = selected ? null : score),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$score',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: Colors.white,
                          decoration: selected
                              ? TextDecoration.underline
                              : null,
                          decorationColor: Colors.white,
                          decorationThickness: 2,
                          shadows: const [
                            Shadow(
                              color: Color(0x806C5670),
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }),
  );
}

/// 编辑器状态快照：用于比对是否有未保存的草稿或更改
class _EditorSnapshot {
  final String feeling;
  final int? mood;
  final List<String> photoKeys;

  _EditorSnapshot({
    required this.feeling,
    required this.mood,
    required this.photoKeys,
  });

  bool matches(
    String currentFeeling,
    int? currentMood,
    List<PhotoEntry> currentPhotos,
  ) {
    if (feeling.trim() != currentFeeling.trim()) return false;
    if (mood != currentMood) return false;
    if (photoKeys.length != currentPhotos.length) return false;
    for (var i = 0; i < currentPhotos.length; i++) {
      final p = currentPhotos[i];
      final key = p.isLocal
          ? 'local:${p.file?.path}:${p.uploadLive}'
          : 'remote:${p.url}';
      if (photoKeys[i] != key) return false;
    }
    return true;
  }
}
