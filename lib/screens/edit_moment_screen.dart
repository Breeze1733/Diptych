import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../services/cache_service.dart';
import '../services/draft_service.dart';
import '../utils/date_helper.dart';
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
    });
  }

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  /// 新建模式下图片变动后即时落地草稿目录，防临时文件被系统清理
  void _syncDraftImages() {
    if (!_isEdit) DraftService.saveImages(_dateStr, _localFiles);
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

    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) throw Exception('未登录');

      final apiService = ref.read(apiServiceProvider);
      final storageService = ref.read(storageServiceProvider);
      final folder = 'user_${currentUser.uid}';

      // 按当前顺序上传新图片，保留已有网络图片
      final imageUrls = await Future.wait(_photos.map(
        (p) => p.isLocal
            ? storageService.uploadImage(p.file!, folder)
            : Future.value(p.url!),
      ));

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

      // 发布成功 → 清除草稿
      await DraftService.clear(_dateStr);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.uploadSuccess), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.uploadFailed}: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            ),
            const SizedBox(height: 20),

            // 感受输入
            Text('💭 今日感受', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _feelingController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: AppStrings.feelingHint,
              ),
            ),
            const SizedBox(height: 12),

            // 已选图片提示
            Center(
              child: Text(
                '已选 ${_photos.length} 张照片，第一张为封面',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),

            // 保存 + 存草稿 按钮
            Row(
              children: [
                // 存草稿（仅新建模式有）
                if (!_isEdit) ...[
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _isSavingDraft ? null : _handleSaveDraft,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.primaryColor),
                        ),
                        child: _isSavingDraft
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('存草稿', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text(AppStrings.saveButton, style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodSelector() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(10, (i) {
        final score = i + 1;
        final isSelected = _mood == score;
        return GestureDetector(
          onTap: () => setState(() => _mood = isSelected ? null : score),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppTheme.primaryColor : Colors.grey[100],
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
          ),
        );
      }),
    );
  }
}
