import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_theme.dart';
import '../utils/diptych_asset_picker.dart';
import '../utils/motion_photo_helper.dart';
import 'live_photo_badge.dart';
import 'image_download_placeholder.dart';
import 'private_network_image.dart';

/// 图片上传状态：idle（空闲/未入队）、queued（排队中）、uploading（上传中）、success（成功）、failed（失败）
enum PhotoUploadStatus { idle, queued, uploading, success, failed }

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
}

/// 图片九宫格选择器
/// 已选图片 + 末尾一个灰色"+"框；点"+"可拍照或从相册多选，图片右上角可删除
class PhotoGridPicker extends StatefulWidget {
  final List<PhotoEntry> entries;
  final ValueChanged<List<PhotoEntry>> onAdded;
  final ValueChanged<int> onRemoved;
  final void Function(int oldIndex, int newIndex) onReordered;
  final PhotoUploadStatus Function(PhotoEntry entry)? statusProvider;
  final double? Function(PhotoEntry entry)? progressProvider;
  final ValueChanged<int>? onRetry;
  final ValueChanged<int>? onTap;
  final Color? Function(int index)? borderColorProvider;
  final String? Function(int index)? badgeLabelProvider;
  final bool Function(int index)? canRemove;
  final bool Function(int index)? canReorder;
  final bool reorderEnabled;
  final bool showCoverBadge;

  /// When bounded, show this many rows and scroll additional photos internally.
  final int? visibleRows;

  const PhotoGridPicker({
    super.key,
    required this.entries,
    required this.onAdded,
    required this.onRemoved,
    required this.onReordered,
    this.statusProvider,
    this.progressProvider,
    this.onRetry,
    this.onTap,
    this.borderColorProvider,
    this.badgeLabelProvider,
    this.canRemove,
    this.canReorder,
    this.reorderEnabled = true,
    this.showCoverBadge = true,
    this.visibleRows,
  });

  @override
  State<PhotoGridPicker> createState() => _PhotoGridPickerState();
}

class _PhotoGridPickerState extends State<PhotoGridPicker> {
  final _scrollController = ScrollController();
  Timer? _dragTimer;
  Offset? _dragPosition;

  List<PhotoEntry> get entries => widget.entries;
  ValueChanged<List<PhotoEntry>> get onAdded => widget.onAdded;
  ValueChanged<int> get onRemoved => widget.onRemoved;
  void Function(int, int) get onReordered => widget.onReordered;
  PhotoUploadStatus Function(PhotoEntry)? get statusProvider =>
      widget.statusProvider;
  double? Function(PhotoEntry)? get progressProvider => widget.progressProvider;
  ValueChanged<int>? get onRetry => widget.onRetry;
  ValueChanged<int>? get onTap => widget.onTap;
  Color? Function(int)? get borderColorProvider => widget.borderColorProvider;
  String? Function(int)? get badgeLabelProvider => widget.badgeLabelProvider;
  bool Function(int)? get canRemove => widget.canRemove;
  bool Function(int)? get canReorder => widget.canReorder;
  bool get reorderEnabled => widget.reorderEnabled;
  bool get showCoverBadge => widget.showCoverBadge;
  int? get visibleRows => widget.visibleRows;

  void _stopDrag() {
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragPosition = null;
  }

  void _autoScroll() {
    final pointer = _dragPosition;
    if (pointer == null || !mounted) return;
    final inner = _scrollController.hasClients
        ? _scrollController.position
        : null;
    final outer = Scrollable.maybeOf(context);
    final position = inner != null && inner.maxScrollExtent > 1
        ? inner
        : outer?.position;
    final box = (identical(position, inner) ? context : outer?.context)
        ?.findRenderObject();
    if (position == null || box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = 48.0;
    final delta = pointer.dy < top + edge
        ? -12.0
        : pointer.dy > bottom - edge
        ? 12.0
        : 0.0;
    if (delta != 0) {
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void dispose() {
    _stopDrag();
    _scrollController.dispose();
    super.dispose();
  }

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
          PhotoEntry.file(file, isMotion: isMotion, uploadLive: isMotion),
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取所选照片的原图，请确认照片已下载到本机后重试')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grid children can be recycled mid-drag. Track the pointer here so movement
    // and termination still arrive after the source Draggable is disposed.
    return Listener(
      onPointerMove: (event) {
        if (_dragTimer != null) _dragPosition = event.position;
      },
      onPointerUp: (_) => _stopDrag(),
      onPointerCancel: (_) => _stopDrag(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rows = visibleRows;
          final bounded = rows != null && constraints.hasBoundedHeight;
          final spacing = bounded
              ? (constraints.maxHeight / 12).clamp(0.0, 8.0)
              : 8.0;
          final minimumSlots = bounded ? rows * 3 : 0;
          final itemCount = entries.length + 1 < minimumSlots
              ? minimumSlots
              : entries.length + 1;
          return GridView.builder(
            controller: _scrollController,
            key: const ValueKey('diary-photo-grid'),
            primary: false,
            padding: EdgeInsets.zero,
            shrinkWrap: !bounded,
            physics: bounded
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: bounded
                  ? ((constraints.maxHeight - spacing * (rows - 1)) / rows)
                        .clamp(.1, double.infinity)
                  : null,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final Widget tile;
              if (index == entries.length) {
                tile = _buildAddTile(context);
              } else if (index > entries.length) {
                tile = DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.softSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              } else {
                tile = _buildPhotoTile(index);
              }
              return KeyedSubtree(
                key: ValueKey('photo-slot-$index'),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }

  /// 灰色"+"框
  Widget _buildAddTile(BuildContext context) {
    return Tooltip(
      message: '添加照片',
      child: Material(
        color: AppTheme.softSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _pickImages(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: (constraints.maxHeight * .5).clamp(0.0, 28.0),
                    color: AppTheme.primaryColor,
                  ),
                  if (constraints.maxHeight >= 62) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '添加照片',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
      } else if (status == PhotoUploadStatus.uploading) {
        // 正在上传的那张图片不可预览大图
        return;
      } else {
        // success, queued, idle 均可正常预览大图
        onTap?.call(index);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => onReordered(details.data, index),
        builder: (context, candidateData, rejectedData) {
          final isDragTarget = candidateData.any((source) => source != index);
          final child = GestureDetector(
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
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          if (!reorderEnabled || canReorder?.call(index) == false) return child;
          return LongPressDraggable<int>(
            data: index,
            onDragStarted: () {
              _dragTimer?.cancel();
              _dragTimer = Timer.periodic(
                const Duration(milliseconds: 24),
                (_) => _autoScroll(),
              );
            },
            feedback: Material(
              color: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _buildPhotoContent(
                  index,
                  status,
                  showDeleteButton: false,
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.25,
              child: _buildPhotoContent(index, status),
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildPhotoContent(
    int index,
    PhotoUploadStatus status, {
    bool showDeleteButton = true,
  }) {
    final entry = entries[index];
    final progress = progressProvider?.call(entry);
    final borderColor = borderColorProvider?.call(index);
    final badgeLabel = badgeLabelProvider?.call(index);
    final image = entry.isLocal
        ? Image.file(entry.file!, fit: BoxFit.cover)
        : PrivateNetworkImage(
            imageUrl: entry.url!,
            usePreview: true,
            fit: BoxFit.cover,
            placeholder: (_, url) => ImageDownloadPlaceholder(url: url),
            errorWidget: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: AppTheme.textSecondary,
            ),
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 3),
      ),
      padding: borderColor == null ? EdgeInsets.zero : const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderColor == null ? 14 : 10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            // 上传中半透明遮罩与圆圈进度显示
            if (status == PhotoUploadStatus.uploading)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3.0,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                    if (progress != null)
                      Text(
                        '${(progress * 100).clamp(0, 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            // 排队中状态：右下角展示“排队中”角标
            if (status == PhotoUploadStatus.queued)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white38, width: 0.8),
                  ),
                  child: const Text(
                    '排队中',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            // 上传失败半透明遮罩与轻点重试提示
            if (status == PhotoUploadStatus.failed)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: (constraints.maxHeight * .6).clamp(0.0, 24.0),
                      ),
                      if (constraints.maxHeight >= 48) ...[
                        const SizedBox(height: 3),
                        const Text(
                          '轻点重试',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // 封面标记（第一张）
            if (badgeLabel != null || (showCoverBadge && index == 0))
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.only(
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Text(
                    badgeLabel ?? '封面',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            // 实况缩略图角标：如果是动态图且选择保留实况，在左下角显示「实况」角标
            if (entry.isMotion && entry.uploadLive)
              Positioned(
                left: 4,
                bottom: 4,
                child: const LivePhotoBadge(isLiveSelected: true),
              ),
            // 删除角标
            if (showDeleteButton && (canRemove?.call(index) ?? true))
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  onPressed: () => onRemoved(index),
                  tooltip: '删除照片',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: const EdgeInsets.all(8),
                  icon: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
