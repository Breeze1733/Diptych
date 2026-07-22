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
import '../widgets/image_slot.dart';

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
  File? _selfImageFile;
  File? _partnerImageFile;
  int? _mood;
  bool _isSaving = false;
  bool _isSavingDraft = false;

  bool get _isEdit => widget.existingMoment != null;

  String get _dateStr => DateHelper.toDateStr(widget.date);

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _feelingController.text = widget.existingMoment!.feeling;
      _mood = widget.existingMoment!.mood;
    } else {
      _loadDraft();
    }
  }

  Future<void> _loadDraft() async {
    final draft = await DraftService.load(_dateStr);
    if (draft == null || !mounted) return;
    setState(() {
      _feelingController.text = draft['feeling'] as String? ?? '';
      _mood = draft['mood'] as int?;
      final selfPath = draft['self_image'] as String?;
      final partnerPath = draft['partner_image'] as String?;
      if (selfPath != null && File(selfPath).existsSync()) {
        _selfImageFile = File(selfPath);
      }
      if (partnerPath != null && File(partnerPath).existsSync()) {
        _partnerImageFile = File(partnerPath);
      }
    });
  }

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  /// API 保存成功后更新本地缓存
  Future<void> _updateCacheAfterSave(String authorId, String selfUrl, String partnerUrl) async {
    final cached = await CacheService.loadDayMoments(_dateStr) ?? [];
    final feeling = _feelingController.text.trim();

    final now = DateHelper.toIsoString(DateTime.now());

    // 构建当前日记的 JSON
    final momentJson = <String, dynamic>{
      'date_str': _dateStr,
      'author_id': authorId,
      'self_image_url': selfUrl,
      'partner_image_url': partnerUrl,
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

      String selfImageUrl;
      String partnerImageUrl;

      if (_isEdit) {
        final oldSelfUrl = widget.existingMoment!.selfImageUrl;
        final oldPartnerUrl = widget.existingMoment!.partnerImageUrl;

        final uploads = await Future.wait([
          _selfImageFile != null
              ? storageService.uploadImage(_selfImageFile!, folder)
              : Future.value(oldSelfUrl),
          _partnerImageFile != null
              ? storageService.uploadImage(_partnerImageFile!, folder)
              : Future.value(oldPartnerUrl),
        ]);
        selfImageUrl = uploads[0];
        partnerImageUrl = uploads[1];

        if (_selfImageFile != null && oldSelfUrl.isNotEmpty) {
          storageService.deleteImage(oldSelfUrl);
        }
        if (_partnerImageFile != null && oldPartnerUrl.isNotEmpty) {
          storageService.deleteImage(oldPartnerUrl);
        }

        await apiService.updateMoment(
          widget.existingMoment!.id,
          {
            'self_image_url': selfImageUrl,
            'partner_image_url': partnerImageUrl,
            'feeling': _feelingController.text.trim(),
            if (_mood != null) 'mood': _mood,
          },
        );
      } else {
        final uploads = await Future.wait([
          _selfImageFile != null
              ? storageService.uploadImage(_selfImageFile!, folder)
              : Future.value(''),
          _partnerImageFile != null
              ? storageService.uploadImage(_partnerImageFile!, folder)
              : Future.value(''),
        ]);
        selfImageUrl = uploads[0];
        partnerImageUrl = uploads[1];

        final existing = await apiService.getMomentByDate(currentUser.uid, _dateStr);
        if (existing != null) {
          if (selfImageUrl.isNotEmpty && existing.selfImageUrl.isNotEmpty) {
            storageService.deleteImage(existing.selfImageUrl);
          }
          if (partnerImageUrl.isNotEmpty && existing.partnerImageUrl.isNotEmpty) {
            storageService.deleteImage(existing.partnerImageUrl);
          }
          await apiService.updateMoment(
            existing.id,
            {
              'self_image_url': selfImageUrl.isNotEmpty ? selfImageUrl : existing.selfImageUrl,
              'partner_image_url': partnerImageUrl.isNotEmpty ? partnerImageUrl : existing.partnerImageUrl,
              'feeling': _feelingController.text.trim(),
              if (_mood != null) 'mood': _mood,
            },
          );
        } else {
          await apiService.createMoment(
            dateStr: _dateStr,
            authorId: currentUser.uid,
            selfImageUrl: selfImageUrl,
            partnerImageUrl: partnerImageUrl,
            feeling: _feelingController.text.trim(),
            mood: _mood,
          );
        }
      }

      // 发布成功 → 更新本地缓存 + 清除草稿
      await _updateCacheAfterSave(currentUser.uid, selfImageUrl, partnerImageUrl);
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
      // 复制图片到草稿目录（防止临时文件被清理）
      if (_selfImageFile != null) {
        await DraftService.saveImage(_dateStr, 'self', _selfImageFile);
      }
      if (_partnerImageFile != null) {
        await DraftService.saveImage(_dateStr, 'partner', _partnerImageFile);
      }
      await DraftService.save(_dateStr, _feelingController.text, _mood);
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

            // 图片插槽 1：关于自己
            Text(AppStrings.selfPhotoLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ImageSlot(
              imageFile: _selfImageFile,
              existingUrl: widget.existingMoment?.selfImageUrl,
              label: '自己',
              onImagePicked: (file) {
                setState(() => _selfImageFile = file);
                if (!_isEdit && file != null) {
                  DraftService.saveImage(_dateStr, 'self', file);
                }
              },
            ),
            const SizedBox(height: 20),

            // 图片插槽 2：关于对方
            Text(AppStrings.partnerPhotoLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ImageSlot(
              imageFile: _partnerImageFile,
              existingUrl: widget.existingMoment?.partnerImageUrl,
              label: '对方',
              onImagePicked: (file) {
                setState(() => _partnerImageFile = file);
                if (!_isEdit && file != null) {
                  DraftService.saveImage(_dateStr, 'partner', file);
                }
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
                '已选 ${(_selfImageFile != null ? 1 : 0) + (_partnerImageFile != null ? 1 : 0)}/2 张照片',
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
