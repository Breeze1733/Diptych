import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../services/cache_service.dart';
import '../services/draft_service.dart';
import '../services/storage_service.dart';
import '../utils/date_helper.dart';
import '../utils/foreground_service_helper.dart';
import '../utils/wakelock_helper.dart';
import '../widgets/photo_grid_picker.dart';

/// 发布/编辑动态页
class EditMomentScreen extends ConsumerStatefulWidget {
  final DateTime date;
  final Moment? existingMoment; // null 表示新建

  const EditMomentScreen({
    super.key,
    required this.date,
    this.existingMoment,
  });

  @override
  ConsumerState<EditMomentScreen> createState() => _EditMomentScreenState();
}

class _EditMomentScreenState extends ConsumerState<EditMomentScreen> {
  final _feelingController = TextEditingController();
  final List<PhotoEntry> _photos = [];
  int? _mood;
  bool _isSaving = false;
  bool _isSavingDraft = false;

  /// 断点续传/预上传：本地图片路径 → 已成功上传的远端 URL
  final Map<String, String> _uploadedUrls = {};

  /// 本地图片路径 → 当前上传状态 (uploading, success, failed, idle)
  final Map<String, PhotoUploadStatus> _uploadStatuses = {};

  /// 待上传队列（本地图片路径列表）
  final List<String> _pendingUploadQueue = [];

  /// 正在进行网络请求的本地图片路径集合
  final Set<String> _inFlightUploads = {};

  /// 已被用户删除/取消、但仍在网络上传中的图片路径集合
  final Set<String> _cancelledUploads = {};

  /// 待异步删除的远端 URL 队列
  final List<String> _pendingDeleteUrls = [];
  bool _isDeleting = false;

  /// 是否正在持有 CPU 唤醒锁与前台保活服务
  bool _hasForegroundKeepAlive = false;

  bool get _isEdit => widget.existingMoment != null;

  String get _dateStr => DateHelper.toDateStr(widget.date);

  /// 当前所有本地新选的图片文件（新建模式下全部都是本地文件）
  List<File> get _localFiles =>
      [for (final p in _photos.where((p) => p.isLocal)) p.file!];

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _feelingController.text = widget.existingMoment!.feeling;
      _mood = widget.existingMoment!.mood;
      _photos.addAll(widget.existingMoment!.imageUrls.map(PhotoEntry.url));
    } else {
      _loadDraft();
    }
  }

  Future<void> _loadDraft() async {
    final draft = await DraftService.load(_dateStr);
    if (draft == null || !mounted) return;
    setState(() {
      _feelingController.text = draft.feeling;
      _mood = draft.mood;
      _photos.addAll(draft.images.map(PhotoEntry.file));
      // 恢复断点续传：草稿图片按序号与持久化的进度一一对应
      for (final e in draft.uploaded.entries) {
        if (e.key >= 0 && e.key < draft.images.length) {
          final path = draft.images[e.key].path;
          _uploadedUrls[path] = e.value;
          _uploadStatuses[path] = PhotoUploadStatus.success;
        }
      }
    });

    // 对草稿中尚未上传成功的本地图片，自动加入预上传队列
    final unUploaded = <File>[];
    for (final p in _photos) {
      if (p.isLocal && !_uploadedUrls.containsKey(p.file!.path)) {
        unUploaded.add(p.file!);
      }
    }
    if (unUploaded.isNotEmpty) {
      _enqueueUploads(unUploaded);
    }
  }

  @override
  void dispose() {
    _feelingController.dispose();
    // 页面销毁时清理未完成的上传标记与保活通知
    _cancelledUploads.addAll(_inFlightUploads);
    _pendingUploadQueue.clear();
    if (_hasForegroundKeepAlive) {
      ForegroundServiceHelper.stop();
      WakelockHelper.release();
    }
    super.dispose();
  }

  /// 新建模式下图片变动后即时落地草稿目录，防临时文件被系统清理；
  /// 同时持久化当前断点续传进度（序号 → URL），让进度与图片顺序保持一致。
  void _syncDraftImages() {
    if (!_isEdit) {
      DraftService.saveImages(_dateStr, _localFiles,
          uploaded: _currentUploadProgress());
    }
  }

  /// 当前断点续传进度：序号 → URL（序号对应草稿图片的序号）
  Map<int, String> _currentUploadProgress() {
    final uploaded = <int, String>{};
    for (var i = 0; i < _photos.length; i++) {
      final p = _photos[i];
      if (p.isLocal) {
        final url = _uploadedUrls[p.file!.path];
        if (url != null) uploaded[i] = url;
      }
    }
    return uploaded;
  }

  /// 将本地文件加入上传队列
  void _enqueueUploads(List<File> files) {
    for (final f in files) {
      final path = f.path;
      if (_uploadedUrls.containsKey(path)) {
        _uploadStatuses[path] = PhotoUploadStatus.success;
        continue;
      }
      _cancelledUploads.remove(path);
      _uploadStatuses[path] = PhotoUploadStatus.uploading;
      if (!_pendingUploadQueue.contains(path) && !_inFlightUploads.contains(path)) {
        _pendingUploadQueue.add(path);
      }
    }
    _processUploadQueue();
  }

  /// 调度上传队列（最大并发数 2）
  static const int _maxConcurrentUploads = 2;

  Future<void> _processUploadQueue() async {
    if (!mounted) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final folder = 'user_${currentUser.uid}';
    final storageService = ref.read(storageServiceProvider);

    _updateKeepAliveState();

    while (_inFlightUploads.length < _maxConcurrentUploads &&
        _pendingUploadQueue.isNotEmpty) {
      final path = _pendingUploadQueue.removeAt(0);
      _inFlightUploads.add(path);
      _uploadStatuses[path] = PhotoUploadStatus.uploading;
      if (mounted) setState(() {});
      _updateKeepAliveState();

      _uploadSingle(path, storageService, folder);
    }
  }

  /// 单张上传
  Future<void> _uploadSingle(
      String path, StorageService storageService, String folder) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final url = await storageService.uploadImage(file, folder);

      if (_cancelledUploads.contains(path)) {
        _cancelledUploads.remove(path);
        _inFlightUploads.remove(path);
        _uploadStatuses.remove(path);
        // 上传期间已被用户删除，立即清理云端孤儿文件
        _enqueueDelete(url);
      } else {
        _inFlightUploads.remove(path);
        _uploadedUrls[path] = url;
        _uploadStatuses[path] = PhotoUploadStatus.success;
        if (!_isEdit) {
          DraftService.saveUploadProgress(_dateStr, _currentUploadProgress());
        }
      }
    } catch (e) {
      debugPrint('[UploadQueue] 上传失败: $path, $e');
      _inFlightUploads.remove(path);
      if (_cancelledUploads.contains(path)) {
        _cancelledUploads.remove(path);
        _uploadStatuses.remove(path);
      } else {
        _uploadStatuses[path] = PhotoUploadStatus.failed;
      }
    } finally {
      if (mounted) setState(() {});
      _processUploadQueue();
      _updateKeepAliveState();
    }
  }

  /// 删图处理
  void _handleRemovePhoto(int index) {
    final photo = _photos.removeAt(index);
    setState(() {});

    if (photo.isLocal) {
      final path = photo.file!.path;
      _pendingUploadQueue.remove(path);
      if (_inFlightUploads.contains(path)) {
        _cancelledUploads.add(path);
      }
      final existingUrl = _uploadedUrls.remove(path);
      _uploadStatuses.remove(path);
      if (existingUrl != null) {
        _enqueueDelete(existingUrl);
      }
    }

    _syncDraftImages();
    _updateKeepAliveState();
  }

  /// 异步删除队列
  void _enqueueDelete(String url) {
    if (url.isEmpty) return;
    _pendingDeleteUrls.add(url);
    _processDeleteQueue();
  }

  Future<void> _processDeleteQueue() async {
    if (_isDeleting || _pendingDeleteUrls.isEmpty) return;
    _isDeleting = true;
    _updateKeepAliveState();

    try {
      final storageService = ref.read(storageServiceProvider);
      while (_pendingDeleteUrls.isNotEmpty) {
        final url = _pendingDeleteUrls.removeAt(0);
        try {
          await storageService.deleteImage(url);
        } catch (e) {
          debugPrint('[DeleteQueue] 删除图片失败: $url, $e');
        }
      }
    } finally {
      _isDeleting = false;
      _updateKeepAliveState();
    }
  }

  /// 重试单张上传
  void _handleRetryUpload(int index) {
    final photo = _photos[index];
    if (photo.isLocal) {
      final path = photo.file!.path;
      _uploadStatuses[path] = PhotoUploadStatus.uploading;
      if (!_pendingUploadQueue.contains(path) && !_inFlightUploads.contains(path)) {
        _pendingUploadQueue.add(path);
      }
      setState(() {});
      _processUploadQueue();
    }
  }

  /// 保活通知与唤醒锁生命周期同步
  Future<void> _updateKeepAliveState() async {
    final isBusy = _inFlightUploads.isNotEmpty ||
        _pendingUploadQueue.isNotEmpty ||
        _isDeleting ||
        _isSaving;

    final localCount = _photos.where((p) => p.isLocal).length;
    final doneCount = _photos
        .where((p) => p.isLocal && _uploadedUrls.containsKey(p.file!.path))
        .length;

    if (isBusy) {
      if (!_hasForegroundKeepAlive) {
        _hasForegroundKeepAlive = true;
        await WakelockHelper.acquire(timeout: const Duration(minutes: 10));
        await ForegroundServiceHelper.start(
          title: 'Diptych 图片同步',
          content: _isSaving
              ? '正在发布日记...'
              : (_isDeleting
                  ? '正在清理图片...'
                  : '正在上传照片 ($doneCount/$localCount)...'),
          maxProgress: localCount > 0 ? localCount : 1,
          progress: doneCount,
        );
      } else {
        await ForegroundServiceHelper.update(
          title: 'Diptych 图片同步',
          content: _isSaving
              ? '正在发布日记...'
              : (_isDeleting
                  ? '正在清理图片...'
                  : '正在上传照片 ($doneCount/$localCount)...'),
          maxProgress: localCount > 0 ? localCount : 1,
          progress: doneCount,
        );
      }
    } else {
      if (_hasForegroundKeepAlive) {
        _hasForegroundKeepAlive = false;
        await ForegroundServiceHelper.stop();
        await WakelockHelper.release();
      }
    }
  }

  /// API 保存成功后更新本地缓存
  Future<void> _updateCacheAfterSave(
      String authorId, List<String> imageUrls) async {
    final cached = await CacheService.loadDayMoments(_dateStr) ?? [];
    final feeling = _feelingController.text.trim();

    final now = DateHelper.toIsoString(DateTime.now());

    // 构建当前日记的 JSON
    final momentJson = <String, dynamic>{
      'date_str': _dateStr,
      'author_id': authorId,
      'image_urls': imageUrls,
      'feeling': feeling,
      if (_mood != null) 'mood': _mood,
      'updated_at': now,
    };

    if (_isEdit) {
      momentJson['id'] = widget.existingMoment!.id;
      momentJson['created_at'] =
          DateHelper.toIsoString(widget.existingMoment!.createdAt);
      momentJson['comments'] =
          widget.existingMoment!.comments.map((c) => c.toJson()).toList();
    } else {
      momentJson['created_at'] = now;
      momentJson['comments'] = <Map<String, dynamic>>[];
    }

    // 替换或追加到缓存列表
    final idx = cached.indexWhere(
        (m) => m['date_str'] == _dateStr && m['author_id'] == authorId);
    if (idx >= 0) {
      // 保留已有的 id（创建时可能还不知道）
      momentJson['id'] ??= cached[idx]['id'];
      cached[idx] = momentJson;
    } else {
      cached.add(momentJson);
    }

    await CacheService.saveDayMoments(_dateStr, cached);
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);

    // 0. 点击发布立即执行一次存草稿，存好草稿再发，以免发布过程中被系统杀后台导致进度完全丢失
    if (!_isEdit) {
      try {
        await DraftService.save(
          _dateStr,
          _feelingController.text.trim(),
          _mood,
          images: _localFiles,
          uploaded: _currentUploadProgress(),
        );
      } catch (e) {
        debugPrint('发布前自动存草稿异常: $e');
      }
    }

    _updateKeepAliveState();

    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) throw Exception('未登录');

      final apiService = ref.read(apiServiceProvider);
      final storageService = ref.read(storageServiceProvider);

      // 1. 将所有尚未成功上传的本地图片（包括失败的项）重新推入上传队列并调度
      for (final p in _photos) {
        if (p.isLocal) {
          final path = p.file!.path;
          if (!_uploadedUrls.containsKey(path) &&
              !_pendingUploadQueue.contains(path) &&
              !_inFlightUploads.contains(path)) {
            _pendingUploadQueue.add(path);
            _uploadStatuses[path] = PhotoUploadStatus.uploading;
          }
        }
      }
      _processUploadQueue();

      // 2. 等待队列中所有图片上传完毕
      while (_inFlightUploads.isNotEmpty || _pendingUploadQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }

      // 3. 检查是否有图片上传失败
      final hasFailed = _photos.any(
          (p) => p.isLocal && !_uploadedUrls.containsKey(p.file!.path));
      if (hasFailed) {
        throw Exception('部分图片上传失败，请点击图片重试后发布');
      }

      // 4. 按当前 UI 图片顺序组装 imageUrls
      final imageUrls = <String>[];
      for (final p in _photos) {
        if (p.isLocal) {
          final url = _uploadedUrls[p.file!.path];
          if (url != null) imageUrls.add(url);
        } else if (p.url != null) {
          imageUrls.add(p.url!);
        }
      }

      ForegroundServiceHelper.update(
        title: 'Diptych 日记发布',
        content: '图片已就绪，正在发布日记...',
        maxProgress: 1,
        progress: 1,
      );

      if (_isEdit) {
        // 删除被移除的旧图
        for (final old in widget.existingMoment!.imageUrls) {
          if (!imageUrls.contains(old)) storageService.deleteImage(old);
        }

        await apiService.updateMoment(
          widget.existingMoment!.id,
          {
            'image_urls': imageUrls,
            'feeling': _feelingController.text.trim(),
            if (_mood != null) 'mood': _mood,
          },
        );
        await _updateCacheAfterSave(currentUser.uid, imageUrls);
      } else {
        // 防并发：其他设备可能已创建当天日记
        final existing =
            await apiService.getMomentByDate(currentUser.uid, _dateStr);
        if (existing != null) {
          final finalUrls =
              imageUrls.isNotEmpty ? imageUrls : existing.imageUrls;
          for (final old in existing.imageUrls) {
            if (!finalUrls.contains(old)) storageService.deleteImage(old);
          }
          await apiService.updateMoment(
            existing.id,
            {
              'image_urls': finalUrls,
              'feeling': _feelingController.text.trim(),
              if (_mood != null) 'mood': _mood,
            },
          );
          await _updateCacheAfterSave(currentUser.uid, finalUrls);
        } else {
          await apiService.createMoment(
            dateStr: _dateStr,
            authorId: currentUser.uid,
            imageUrls: imageUrls,
            feeling: _feelingController.text.trim(),
            mood: _mood,
          );
          await _updateCacheAfterSave(currentUser.uid, imageUrls);
        }
      }

      // 清理断点续传中已上传、但最终未使用的孤儿图片（如重试前被移除的图）
      for (final url in _uploadedUrls.values) {
        if (!imageUrls.contains(url)) storageService.deleteImage(url);
      }

      // 发布成功 → 清除草稿
      await DraftService.clear(_dateStr);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(AppStrings.uploadSuccess),
            backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // 发布失败时再次保存草稿（包含最新断点续传进度），防止用户内容丢失
      if (!_isEdit) {
        try {
          await DraftService.save(
            _dateStr,
            _feelingController.text.trim(),
            _mood,
            images: _localFiles,
            uploaded: _currentUploadProgress(),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.uploadFailed}，已自动保存为草稿: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
      _updateKeepAliveState();
    }
  }

  /// 存草稿
  Future<void> _handleSaveDraft() async {
    setState(() => _isSavingDraft = true);
    try {
      // save 内部会把图片复制进草稿目录（单一可靠入口）
      await DraftService.save(
        _dateStr,
        _feelingController.text,
        _mood,
        images: _localFiles,
        uploaded: _currentUploadProgress(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('草稿已保存'), backgroundColor: AppTheme.primaryColor),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存草稿失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localCount = _photos.where((p) => p.isLocal).length;
    final doneCount = _photos
        .where((p) => p.isLocal && _uploadedUrls.containsKey(p.file!.path))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? AppStrings.editTitle : AppStrings.createTitle),
        actions: [
          if (!_isEdit)
            SizedBox(
              width: 72,
              child: TextButton(
                onPressed:
                    _isSavingDraft || _isSaving ? null : _handleSaveDraft,
                child: _isSavingDraft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('存草稿'),
              ),
            ),
          SizedBox(
            width: 84,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _isSaving || _isSavingDraft ? null : _handleSave,
              child: _isSaving
                  ? (_inFlightUploads.isNotEmpty || _pendingUploadQueue.isNotEmpty
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '上传中 $doneCount/$localCount',
                            style: const TextStyle(fontSize: 12),
                          ),
                        )
                      : const Text(
                          '发布中…',
                          style: TextStyle(fontSize: 12),
                        ))
                  : const Text(
                      AppStrings.saveButton,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                DateHelper.toChineseDate(widget.date),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),

            // 心情打分
            Text(AppStrings.feelingLabel,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _buildMoodSelector(),
            const SizedBox(height: 16),

            // 图片九宫格（第一张为封面）
            Text(AppStrings.photosLabel,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            PhotoGridPicker(
              entries: _photos,
              statusProvider: (entry) {
                if (!entry.isLocal) return PhotoUploadStatus.success;
                return _uploadStatuses[entry.file!.path] ??
                    (_uploadedUrls.containsKey(entry.file!.path)
                        ? PhotoUploadStatus.success
                        : PhotoUploadStatus.idle);
              },
              onRetry: _handleRetryUpload,
              onAdded: (files) {
                setState(() => _photos.addAll(files.map(PhotoEntry.file)));
                _syncDraftImages();
                _enqueueUploads(files);
              },
              onRemoved: (index) {
                _handleRemovePhoto(index);
              },
              onReordered: (oldIndex, newIndex) {
                setState(() {
                  final photo = _photos.removeAt(oldIndex);
                  _photos.insert(newIndex, photo);
                });
                _syncDraftImages();
              },
            ),
            const SizedBox(height: 20),

            // 感受输入
            Text('今日感受',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            // 排除全局选择容器：输入框用自己的原生选择（与输入法兼容）
            SelectionContainer.disabled(
              child: TextField(
                controller: _feelingController,
                minLines: 5,
                maxLines: null,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                // 显式声明长按菜单：剪切/复制/粘贴/全选
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: editableTextState.contextMenuButtonItems,
                ),
                decoration: InputDecoration(
                  hintText: AppStrings.feelingHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodSelector() {
    return Row(
      children: List.generate(10, (i) {
        final score = i + 1;
        final isSelected = _mood == score;
        final moodColor = AppTheme.moodColor(score);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onTap: () => setState(() => _mood = isSelected ? null : score),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? moodColor : Colors.grey[100],
                    border: Border.all(
                      color: isSelected ? moodColor : Colors.grey[300]!,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey[600],
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
}
