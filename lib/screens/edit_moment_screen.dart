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

  /// 断点续传：本次会话中已成功上传的本地图片路径 → URL，重试时直接复用
  final Map<String, String> _uploadedUrls = {};
  /// 串行上传进度（按钮上显示 上传中 已传/总数）
  int _uploadDone = 0;
  int _uploadTotal = 0;

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
          _uploadedUrls[draft.images[e.key].path] = e.value;
        }
      }
    });
  }

  @override
  void dispose() {
    _feelingController.dispose();
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

  /// API 保存成功后更新本地缓存
  Future<void> _updateCacheAfterSave(String authorId, List<String> imageUrls) async {
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
      momentJson['created_at'] = DateHelper.toIsoString(widget.existingMoment!.createdAt);
      momentJson['comments'] = widget.existingMoment!.comments.map((c) => c.toJson()).toList();
    } else {
      momentJson['created_at'] = now;
      momentJson['comments'] = <Map<String, dynamic>>[];
    }

    // 替换或追加到缓存列表
    final idx = cached.indexWhere((m) =>
        m['date_str'] == _dateStr && m['author_id'] == authorId);
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

    // 申请 CPU 唤醒锁（默认 10 分钟），防止传图过程中用户切后台/锁屏时被系统挂起
    await WakelockHelper.acquire(timeout: const Duration(minutes: 10));

    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) throw Exception('未登录');

      final apiService = ref.read(apiServiceProvider);
      final storageService = ref.read(storageServiceProvider);
      final folder = 'user_${currentUser.uid}';

      // 串行上传：一张一张传；失败重试时已成功的图片直接复用 URL（断点续传）
      setState(() {
        _uploadDone = 0;
        _uploadTotal = _photos.where((p) => p.isLocal).length;
      });
      final imageUrls = await _uploadImages(storageService, folder);

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
        final existing = await apiService.getMomentByDate(currentUser.uid, _dateStr);
        if (existing != null) {
          final finalUrls = imageUrls.isNotEmpty ? imageUrls : existing.imageUrls;
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
        const SnackBar(content: Text(AppStrings.uploadSuccess), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // 发布失败时自动保存草稿（文本、心情、图片及断点续传进度），防止用户内容丢失
      if (!_isEdit) {
        try {
          await DraftService.save(
            _dateStr,
            _feelingController.text.trim(),
            _mood,
            images: _localFiles,
          );
          await DraftService.saveUploadProgress(_dateStr, _currentUploadProgress());
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
      // 无论成功还是失败，务必释放 CPU 唤醒锁
      await WakelockHelper.release();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 串行上传所有图片，返回按 [_photos] 顺序的 URL 列表。
  /// 一旦某张失败会抛出异常，中断后续上传；再次点上传时，
  /// 已成功过的图片从 [_uploadedUrls] 复用 URL，只重传失败的（断点续传）。
  Future<List<String>> _uploadImages(
      StorageService storageService, String folder) async {
    final urls = <String>[];
    for (final p in _photos) {
      if (!p.isLocal) {
        urls.add(p.url!); // 编辑模式下保留的旧网络图，无需上传
        continue;
      }
      final cached = _uploadedUrls[p.file!.path];
      if (cached != null) {
        urls.add(cached); // 断点续传：复用上次已上传成功的 URL
        _uploadDone++;
        if (mounted) setState(() {});
        continue;
      }
      final url = await storageService.uploadImage(p.file!, folder);
      _uploadedUrls[p.file!.path] = url;
      urls.add(url);
      _uploadDone++;
      if (mounted) setState(() {});
      // 每传成功一张就持久化进度，App 退出/被杀后再进来仍能断点续传
      if (!_isEdit) {
        DraftService.saveUploadProgress(_dateStr, _currentUploadProgress());
      }
    }
    return urls;
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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存'), backgroundColor: AppTheme.primaryColor),
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
            width: 80,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _isSaving || _isSavingDraft ? null : _handleSave,
              child: _isSaving
                  ? (_uploadTotal > 0 && _uploadDone < _uploadTotal
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '上传中 $_uploadDone/$_uploadTotal',
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),

            // 心情打分
            Text(AppStrings.feelingLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _buildMoodSelector(),
            const SizedBox(height: 16),

            // 图片九宫格（第一张为封面）
            Text(AppStrings.photosLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            PhotoGridPicker(
              entries: _photos,
              onAdded: (files) {
                setState(() => _photos.addAll(files.map(PhotoEntry.file)));
                _syncDraftImages();
              },
              onRemoved: (index) {
                setState(() => _photos.removeAt(index));
                _syncDraftImages();
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
            Text('今日感受', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
