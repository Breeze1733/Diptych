import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 图片选择插槽
/// 点击可选择/更换图片，显示预览
class ImageSlot extends StatelessWidget {
  final File? imageFile;
  final String? existingUrl;
  final String label;
  final ValueChanged<File?> onImagePicked;

  const ImageSlot({
    super.key,
    this.imageFile,
    this.existingUrl,
    required this.label,
    required this.onImagePicked,
  });

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();

    // 弹出选择方式
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      onImagePicked(File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageFile != null || (existingUrl != null && existingUrl!.isNotEmpty);

    return GestureDetector(
      onTap: () => _pickImage(context),
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage ? _buildPreview() : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPreview() {
    if (imageFile != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(imageFile!, fit: BoxFit.cover),
          _buildChangeLabel(),
          Positioned(top: 4, left: 8, child: _labelChip()),
        ],
      );
    }
    // 显示已有图片（编辑模式）
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: existingUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => _buildPlaceholder(),
          errorWidget: (_, __, ___) => _buildPlaceholder(),
        ),
        _buildChangeLabel(),
        Positioned(top: 4, left: 8, child: _labelChip()),
      ],
    );
  }

  Widget _labelChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }

  Widget _buildChangeLabel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black45,
        padding: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.center,
        child: const Text('点击更换', style: TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        const SizedBox(height: 4),
        Text('点击选择', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
      ],
    );
  }
}
