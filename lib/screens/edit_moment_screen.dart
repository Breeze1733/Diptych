import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
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

  bool get _isEdit => widget.existingMoment != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _feelingController.text = widget.existingMoment!.feeling;
      _mood = widget.existingMoment!.mood;
    }
  }

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) throw Exception('未登录');

      final apiService = ref.read(apiServiceProvider);
      final storageService = ref.read(storageServiceProvider);
      final dateStr = DateHelper.toDateStr(widget.date);
      final folder = 'user_${currentUser.uid}';

      String selfImageUrl;
      String partnerImageUrl;

      if (_isEdit) {
        // 编辑模式：仅上传新选择的图片，否则保留旧 URL
        final oldSelfUrl = widget.existingMoment!.selfImageUrl;
        final oldPartnerUrl = widget.existingMoment!.partnerImageUrl;
        selfImageUrl = oldSelfUrl;
        partnerImageUrl = oldPartnerUrl;

        if (_selfImageFile != null) {
          selfImageUrl = await storageService.uploadImage(_selfImageFile!, folder);
          if (oldSelfUrl.isNotEmpty) storageService.deleteImage(oldSelfUrl);
        }
        if (_partnerImageFile != null) {
          partnerImageUrl = await storageService.uploadImage(_partnerImageFile!, folder);
          if (oldPartnerUrl.isNotEmpty) storageService.deleteImage(oldPartnerUrl);
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
        // 新建模式
        selfImageUrl = _selfImageFile != null
            ? await storageService.uploadImage(_selfImageFile!, folder)
            : '';
        partnerImageUrl = _partnerImageFile != null
            ? await storageService.uploadImage(_partnerImageFile!, folder)
            : '';

        // 先检查是否已存在（防止因缓存/网络问题导致的 409）
        final existing = await apiService.getMomentByDate(currentUser.uid, dateStr);
        if (existing != null) {
          // 已存在 → 走更新逻辑
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
            dateStr: dateStr,
            authorId: currentUser.uid,
            selfImageUrl: selfImageUrl,
            partnerImageUrl: partnerImageUrl,
            feeling: _feelingController.text.trim(),
            mood: _mood,
          );
        }
      }

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
            // 日期显示
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
              onImagePicked: (file) => setState(() => _selfImageFile = file),
            ),
            const SizedBox(height: 20),

            // 图片插槽 2：关于对方
            Text(AppStrings.partnerPhotoLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ImageSlot(
              imageFile: _partnerImageFile,
              existingUrl: widget.existingMoment?.partnerImageUrl,
              label: '对方',
              onImagePicked: (file) => setState(() => _partnerImageFile = file),
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

            // 保存按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSaving ? null : _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(AppStrings.saveButton, style: TextStyle(fontSize: 16)),
              ),
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
