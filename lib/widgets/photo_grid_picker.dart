import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 一张图片条目：本地新选的文件，或编辑时已上传的网络图
class PhotoEntry {
  final File? file;
  final String? url;

  const PhotoEntry.file(File this.file) : url = null;
  const PhotoEntry.url(String this.url) : file = null;

  bool get isLocal => file != null;
}

/// 微信风格图片九宫格选择器
/// 已选图片 + 末尾一个灰色"+"框；点"+"可拍照或从相册多选，图片右上角可删除
class PhotoGridPicker extends StatelessWidget {
  final List<PhotoEntry> entries;
  final ValueChanged<List<File>> onAdded;
  final ValueChanged<int> onRemoved;

  const PhotoGridPicker({
    super.key,
    required this.entries,
    required this.onAdded,
    required this.onRemoved,
  });

  Future<void> _pickImages(BuildContext context) async {
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
              title: const Text('从相册选择（可多选）'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked != null) onAdded([File(picked.path)]);
    } else {
      final picked = await picker.pickMultiImage();
      if (picked.isNotEmpty) onAdded(picked.map((x) => File(x.path)).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) return _buildAddTile(context);
        return _buildPhotoTile(index);
      },
    );
  }

  /// 灰色"+"框
  Widget _buildAddTile(BuildContext context) {
    return GestureDetector(
      onTap: () => _pickImages(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(Icons.add, size: 36, color: Colors.grey[400]),
      ),
    );
  }

  /// 图片缩略图 + 删除角标 + 封面标记
  Widget _buildPhotoTile(int index) {
    final entry = entries[index];
    final image = entry.isLocal
        ? Image.file(entry.file!, fit: BoxFit.cover)
        : CachedNetworkImage(
            imageUrl: entry.url!,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: Colors.grey[100]),
            errorWidget: (_, _, _) =>
                Icon(Icons.broken_image, color: Colors.grey[300]),
          );

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          // 封面标记（第一张）
          if (index == 0)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.only(topRight: Radius.circular(6)),
                ),
                child: const Text(
                  '封面',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          // 删除角标
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => onRemoved(index),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius:
                      BorderRadius.only(bottomLeft: Radius.circular(6)),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
