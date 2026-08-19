import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../utils/file_helper.dart';
import 'photo_grid_picker.dart';

/// 弹出半透明底色的图片列表（一行三张，可滑动），点击单张进入全屏查看
void showImageGallery(BuildContext context, List<String> urls) {
  if (urls.isEmpty) return;
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      pageBuilder: (_, _, _) => _ImageGalleryOverlay(urls: urls),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// 全屏查看图片（支持网络 URL 列表 或 PhotoEntry 列表）
void showFullScreenPreview(
  BuildContext context, {
  List<String>? urls,
  List<PhotoEntry>? entries,
  int initialIndex = 0,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FullScreenImage(
        urls: urls,
        entries: entries,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// 半透明网格图片列表
class _ImageGalleryOverlay extends StatelessWidget {
  final List<String> urls;
  const _ImageGalleryOverlay({required this.urls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withAlpha(180),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '全部图片（${urls.length}）',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: GestureDetector(
        // 点击空白处关闭
        onTap: () => Navigator.pop(context),
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImage(
                    urls: urls,
                    initialIndex: index,
                  ),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white10,
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: urls[index],
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white38,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 全屏图片查看器：photo_view 驱动，手势与微信朋友圈一致
/// - 单指 1.0 倍 → 左右切页
/// - 单指放大后 → 图片内拖拽，到边缘继续拖 → 切页
/// - 双指 → 以捏合点为中心缩放
class FullScreenImage extends StatefulWidget {
  final List<String>? urls;
  final List<PhotoEntry>? entries;
  final int initialIndex;

  const FullScreenImage({
    super.key,
    this.urls,
    this.entries,
    this.initialIndex = 0,
  }) : assert(urls != null || entries != null, 'urls 与 entries 至少提供一个');

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  late int _currentIndex;
  late PageController _pageController;
  bool _isDownloading = false;

  int get _totalCount => widget.entries?.length ?? widget.urls?.length ?? 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String? get _currentUrl {
    if (widget.urls != null) return widget.urls![_currentIndex];
    final entry = widget.entries![_currentIndex];
    return entry.url;
  }

  bool get _canDownload => _currentUrl != null && _currentUrl!.isNotEmpty;

  ImageProvider _getImageProvider(int index) {
    if (widget.entries != null) {
      final entry = widget.entries![index];
      if (entry.isLocal) {
        return FileImage(entry.file!);
      } else {
        return CachedNetworkImageProvider(entry.url!);
      }
    }
    return CachedNetworkImageProvider(widget.urls![index]);
  }

  Future<void> _download() async {
    final url = _currentUrl;
    if (url == null || url.isEmpty) return;

    setState(() => _isDownloading = true);
    try {
      final res = await http.get(Uri.parse(url));
      final dir = await FileHelper.getDownloadsDirectory();
      String name = url.split('/').last;
      if (name.contains('?')) name = name.substring(0, name.indexOf('?'));
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(res.bodyBytes);
      await FileHelper.scanFile(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _totalCount > 1
            ? Text(
                '${_currentIndex + 1} / $_totalCount',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
        actions: [
          if (_canDownload)
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download),
              tooltip: '下载',
              onPressed: _isDownloading ? null : _download,
            ),
        ],
      ),
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            itemCount: _totalCount,
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: _getImageProvider(index),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4.0,
              errorBuilder: (_, error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image,
                        size: 48, color: Colors.white54),
                    const SizedBox(height: 8),
                    const Text('图片加载失败',
                        style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
            pageController: _pageController,
            onPageChanged: (index) =>
                setState(() => _currentIndex = index),
            backgroundDecoration:
                const BoxDecoration(color: Colors.black),
            gaplessPlayback: true,
          ),
          // 底部页码指示器
          if (_totalCount > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / $_totalCount',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
