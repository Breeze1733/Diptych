import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/diptych_asset_picker.dart';
import '../utils/motion_photo_helper.dart';

/// 图片上传状态
enum PhotoUploadStatus {
  idle,
  uploading,
  success,
  failed,
}

/// 一张图片条目：本地新选的文件，或编辑时已上传的网络图
class PhotoEntry {
  final File? file;
  final String? url;
  final bool isMotion;
  final bool uploadLive;

  const PhotoEntry.file(
    File this.file, {
    this.isMotion = false,
    this.uploadLive = false,
  }) : url = null;

  const PhotoEntry.url(
    String this.url, {
    this.isMotion = false,
    this.uploadLive = false,
  }) : file = null;

  bool get isLocal => file != null;

  PhotoEntry copyWith({
    File? file,
    String? url,
    bool? isMotion,
    bool? uploadLive,
  }) {
    if (isLocal) {
      return PhotoEntry.file(
        file ?? this.file!,
        isMotion: isMotion ?? this.isMotion,
        uploadLive: uploadLive ?? this.uploadLive,
      );
    } else {
      return PhotoEntry.url(
        url ?? this.url!,
        isMotion: isMotion ?? this.isMotion,
        uploadLive: uploadLive ?? this.uploadLive,
      );
    }
  }
}

/// 微信风格图片九宫格选择器
/// 已选图片 + 末尾一个灰色"+"框；点"+"可拍照或从相册多选，图片右上角可删除
class PhotoGridPicker extends StatelessWidget {
  final List<PhotoEntry> entries;
  final ValueChanged<List<PhotoEntry>> onAdded;
  final ValueChanged<int> onRemoved;
  final void Function(int oldIndex, int newIndex) onReordered;
  final PhotoUploadStatus Function(PhotoEntry entry)? statusProvider;
  final ValueChanged<int>? onRetry;
  final ValueChanged<int>? onTap;

  const PhotoGridPicker({
    super.key,
    required this.entries,
    required this.onAdded,
    required this.onRemoved,
    required this.onReordered,
    this.statusProvider,
    this.onRetry,
    this.onTap,
  });

  Future<void> _pickImages(BuildContext context) async {
    final picker = ImagePicker();

    // 弹出选择方式
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择（可多选）'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (source == null || !context.mounted) return;

    if (source == 'camera') {
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked != null) {
        final file = File(picked.path);
        final isMotion = await MotionPhotoHelper.isMotionPhoto(file);
        onAdded([
          PhotoEntry.file(
            file,
            isMotion: isMotion,
            uploadLive: false,
          ),
        ]);
      }
    } else {
      try {
        final pickedEntries = await DiptychAssetPicker.pickPhotos(
          context,
          maxAssets: 999, // 不限图片张数，支持海量多选
        );
        if (pickedEntries != null && pickedEntries.isNotEmpty) {
          onAdded(pickedEntries);
        }
      } catch (e) {
        debugPrint('PhotoGridPicker.pickPhotos 异常: $e');
      }
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

  /// 图片缩略图 + 删除角标 + 封面标记 + 上传状态
  Widget _buildPhotoTile(int index) {
    final entry = entries[index];
    final status = statusProvider?.call(entry) ?? PhotoUploadStatus.success;

    void handleTap() {
      if (status == PhotoUploadStatus.failed) {
        onRetry?.call(index);
      } else if (status == PhotoUploadStatus.success) {
        onTap?.call(index);
      }
      // 上传中 (uploading) 或未就绪 (idle) 时不触发打开大图，确保上传过程中无法点击大图，上传成功后可预览
    }

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => onReordered(details.data, index),
        builder: (context, candidateData, rejectedData) {
          final isDragTarget = candidateData.any((source) => source != index);

          return LongPressDraggable<int>(
            data: index,
            feedback: Material(
              color: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _buildPhotoContent(index, status, showDeleteButton: false),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.25,
              child: _buildPhotoContent(index, status),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: handleTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPhotoContent(index, status),
                  if (isDragTarget)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoContent(int index, PhotoUploadStatus status,
      {bool showDeleteButton = true}) {
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
          // 上传中半透明遮罩与进度环
          if (status == PhotoUploadStatus.uploading)
            Container(
              color: Colors.black38,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
          // 上传失败半透明遮罩与轻点重试提示
          if (status == PhotoUploadStatus.failed)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 24),
                  SizedBox(height: 3),
                  Text(
                    '轻点重试',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          // 封面标记（第一张）
          if (index == 0)
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(6)),
                ),
                child: const Text(
                  '封面',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          // 实况徽标（若为实况照片，点击可单独切换该图片的实况状态）
          // 实况静态徽标（如果选图时指定为实况，则在九宫格显示微信同款静态角标，轻触图片主体进入大图预览）
          if (entry.uploadLive)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white38,
                    width: 0.8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.motion_photos_on,
                      size: 12,
                      color: Colors.white,
                    ),
                    SizedBox(width: 3),
                    Text(
                      '实况',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 删除角标
          if (showDeleteButton)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => onRemoved(index),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
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
