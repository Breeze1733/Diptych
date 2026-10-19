import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';

import '../services/private_image_cache.dart';
import '../services/transfer_keep_alive.dart';
import '../utils/file_helper.dart';
import '../utils/motion_photo_helper.dart';
import 'photo_grid_picker.dart';
import 'image_preview_chrome.dart';
import 'image_download_placeholder.dart';
import 'private_network_image.dart';

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
                  builder: (_) =>
                      FullScreenImage(urls: urls, initialIndex: index),
                ),
              ),
              child: _GalleryGridItem(url: urls[index]),
            );
          },
        ),
      ),
    );
  }
}

/// 带实况状态识别的相册缩略图
class _GalleryGridItem extends StatefulWidget {
  final String url;
  const _GalleryGridItem({required this.url});

  @override
  State<_GalleryGridItem> createState() => _GalleryGridItemState();
}

class _GalleryGridItemState extends State<_GalleryGridItem> {
  bool _isMotion = false;

  @override
  void initState() {
    super.initState();
    _checkMotion();
  }

  @override
  void didUpdateWidget(_GalleryGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _checkMotion();
    }
  }

  Future<void> _checkMotion() async {
    final isMotion = await MotionPhotoHelper.isMotionPhotoUrl(widget.url);
    if (mounted && isMotion) {
      setState(() => _isMotion = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white10,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PrivateNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.cover,
            placeholder: (_, url) => ImageDownloadPlaceholder(
              url: url,
              color: Colors.white70,
              backgroundColor: Colors.transparent,
            ),
            errorWidget: (_, _, _) =>
                const Icon(Icons.broken_image, color: Colors.white38),
          ),
          if (_isMotion)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white38, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, size: 12, color: Colors.white),
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
        ],
      ),
    );
  }
}

/// 全屏图片查看器：photo_view 驱动，手势与微信朋友圈一致
/// - 单指 1.0 倍 → 左右切页
/// - 单指放大后 → 图片内拖拽，到边缘继续拖 → 切页
/// - 双指 → 以捏合点为中心缩放
/// - 左下角提供微信同款无感「实况」轻触播放（单次播放，播完自动平滑恢复静态图）
class FullScreenImage extends StatefulWidget {
  final List<String>? urls;
  final List<PhotoEntry>? entries;
  final int initialIndex;
  final PrivateImageCache? cacheManager;

  const FullScreenImage({
    super.key,
    this.urls,
    this.entries,
    this.initialIndex = 0,
    this.cacheManager,
  }) : assert(urls != null || entries != null, 'urls 与 entries 至少提供一个');

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  late int _currentIndex;
  late PageController _pageController;
  bool _isDownloading = false;
  String? _downloadingUrl;
  bool _controlsVisible = true;
  StreamSubscription<String>? _cacheSubscription;
  final _originalRequests = <String, Future<File>>{};
  PrivateImageCache get _cache => widget.cacheManager ?? PrivateImageCache();

  // 实况状态
  VideoPlayerController? _videoController;
  bool _isMotionPhoto = false;
  bool _isPlaying = false;
  int _checkingIndex = -1;

  bool get _showLiveButton {
    if (widget.entries != null && _currentIndex < widget.entries!.length) {
      return widget.entries![_currentIndex].isMotion;
    }
    return _isMotionPhoto;
  }

  int get _totalCount => widget.entries?.length ?? widget.urls?.length ?? 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _cacheSubscription = _cache.changes.listen((url) {
      if (mounted &&
          (url.isEmpty ||
              widget.urls?.contains(url) == true ||
              widget.entries?.any((entry) => entry.url == url) == true)) {
        setState(() {});
      }
    });
    _checkMotionPhotoForIndex(_currentIndex);
  }

  @override
  void dispose() {
    _cacheSubscription?.cancel();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String? get _currentUrl {
    if (widget.urls != null && _currentIndex < widget.urls!.length) {
      return widget.urls![_currentIndex];
    }
    if (widget.entries != null && _currentIndex < widget.entries!.length) {
      final entry = widget.entries![_currentIndex];
      return entry.url;
    }
    return null;
  }

  bool get _canDownload {
    if (_currentUrl != null && _currentUrl!.isNotEmpty) return true;
    if (widget.entries != null && _currentIndex < widget.entries!.length) {
      return widget.entries![_currentIndex].isLocal;
    }
    return false;
  }

  ImageProvider _getImageProvider(int index) {
    if (widget.entries != null) {
      final entry = widget.entries![index];
      if (entry.isLocal) {
        return FileImage(entry.file!);
      } else {
        return CachedNetworkImageProvider(
          entry.url!,
          cacheManager: _cache,
          cacheKey: _cache.displayKey(entry.url!),
        );
      }
    }
    return CachedNetworkImageProvider(
      widget.urls![index],
      cacheManager: _cache,
      cacheKey: _cache.displayKey(widget.urls![index]),
    );
  }

  /// Entering the viewer only inspects originals already on this device.
  Future<File?> _resolveFile(int index) async {
    if (widget.entries != null && index < widget.entries!.length) {
      final entry = widget.entries![index];
      if (entry.isLocal && entry.file != null) return entry.file;
      if (entry.url != null && entry.url!.isNotEmpty) {
        final fileInfo = await _cache.getOriginalFromCache(entry.url!);
        if (fileInfo != null) return fileInfo.file;
      }
    } else if (widget.urls != null && index < widget.urls!.length) {
      final url = widget.urls![index];
      final fileInfo = await _cache.getOriginalFromCache(url);
      if (fileInfo != null) return fileInfo.file;
    }
    return null;
  }

  /// 异步检测当前索引图片是否包含实况 MP4
  Future<void> _checkMotionPhotoForIndex(int index) async {
    _checkingIndex = index;

    // 清理上一张图的视频控制器
    final oldController = _videoController;
    _videoController = null;
    if (mounted) {
      setState(() {
        _isMotionPhoto = false;
        _isPlaying = false;
      });
    }
    await oldController?.dispose();

    final file = await _resolveFile(index);
    if (!mounted || _checkingIndex != index) return;
    if (file == null) {
      final url = widget.urls?[index] ?? widget.entries?[index].url;
      if (url == null) return;
      final info = await _cache.getInfo(url);
      if (mounted && _checkingIndex == index) {
        setState(() => _isMotionPhoto = info?.isMotion ?? false);
      }
      return;
    }

    // 先快速检测二进制特征，若为实况照片立即点亮实况标识
    final isMotion = await MotionPhotoHelper.isMotionPhoto(file);
    if (!isMotion || !mounted || _checkingIndex != index) return;

    setState(() {
      _isMotionPhoto = true;
    });

    final videoFile = await MotionPhotoHelper.getOrExtractMotionVideo(file);
    if (videoFile == null || !mounted || _checkingIndex != index) return;

    final controller = VideoPlayerController.file(videoFile);
    try {
      await controller.initialize();
      if (!mounted || _checkingIndex != index) {
        await controller.dispose();
        return;
      }

      // 监听播放结束事件（播放一遍后自动无缝恢复静态图）
      controller.addListener(() {
        if (!mounted) return;
        if (controller.value.isInitialized) {
          final isEnded =
              controller.value.position >= controller.value.duration;
          if (isEnded && _isPlaying) {
            setState(() {
              _isPlaying = false;
            });
            controller.pause();
            controller.seekTo(Duration.zero);
          }
        }
      });

      setState(() {
        _videoController = controller;
        _isMotionPhoto = true;
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  /// 轻点左下角实况按钮：无感播放一遍（播完自动停住恢复静态图）
  Future<void> _toggleLivePlayback() async {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      final index = _currentIndex;
      final url = _currentUrl;
      if (url == null) return;
      try {
        await _ensureOriginal(url);
        if (!mounted || _currentIndex != index) return;
        await _checkMotionPhotoForIndex(index);
      } catch (_) {
        if (mounted) _showOriginalError();
        return;
      }
      if (!mounted || _currentIndex != index || _videoController == null) {
        return;
      }
    }
    if (_isPlaying) {
      await _videoController!.pause();
      await _videoController!.seekTo(Duration.zero);
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _videoController!.seekTo(Duration.zero);
      await _videoController!.play();
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _checkMotionPhotoForIndex(index);
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    final url = _currentUrl;
    final manufacturer = await FileHelper.getDeviceManufacturer();

    if (url == null || url.isEmpty) {
      if (widget.entries != null && _currentIndex < widget.entries!.length) {
        final entry = widget.entries![_currentIndex];
        if (entry.isLocal && entry.file != null) {
          setState(() => _isDownloading = true);
          try {
            final dir = await FileHelper.getDownloadsDirectory();
            final name = entry.file!.path
                .split(Platform.pathSeparator)
                .last
                .split('/')
                .last;
            final targetFile = File('${dir.path}/$name');
            await MotionPhotoHelper.saveAdaptedMotionPhoto(
              entry.file!,
              targetFile,
              targetManufacturer: manufacturer,
            );
            await FileHelper.scanFile(targetFile.path);
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('已保存到 ${targetFile.path}')));
          } catch (e) {
            debugPrint('保存图片失败: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('保存失败，请检查存储权限后重试'),
                backgroundColor: Colors.red,
              ),
            );
          } finally {
            if (mounted) setState(() => _isDownloading = false);
          }
        }
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadingUrl = url;
    });
    try {
      final sourceFile = await _ensureOriginal(url);

      final dir = await FileHelper.getDownloadsDirectory();
      String name = url.split('/').last;
      if (name.contains('?')) name = name.substring(0, name.indexOf('?'));
      final targetFile = File('${dir.path}/$name');

      await MotionPhotoHelper.saveAdaptedMotionPhoto(
        sourceFile,
        targetFile,
        targetManufacturer: manufacturer,
      );
      await FileHelper.scanFile(targetFile.path);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已保存到 ${targetFile.path}')));
    } catch (e) {
      debugPrint('下载图片失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下载失败，请检查网络后重试'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingUrl = null;
        });
      }
    }
  }

  Future<File> _ensureOriginal(String url) async {
    final cached = await _cache.getOriginalFromCache(url);
    if (cached != null) return cached.file;
    final existing = _originalRequests[url];
    if (existing != null) return existing;
    final request = () async {
      final lease = await TransferKeepAlive.acquire(
        title: 'Diptych 原图下载',
        content: '正在获取原图…',
      );
      final subscription = _cache.downloads
          .watch(_cache.progressKey(url, original: true))
          .listen((progress) {
            unawaited(
              lease.update(
                content: progress.percent == null
                    ? '正在获取原图…'
                    : '正在获取原图 ${progress.percent}%',
                maxProgress: 100,
                progress: progress.percent ?? 0,
              ),
            );
          });
      try {
        return await _cache.getOriginalFile(url);
      } finally {
        await subscription.cancel();
        await lease.release();
      }
    }();
    _originalRequests[url] = request;
    if (mounted) setState(() {});
    try {
      return await request;
    } finally {
      if (identical(_originalRequests[url], request)) {
        _originalRequests.remove(url);
      }
      if (mounted) setState(() {});
    }
  }

  void _showOriginalError() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('原图加载失败，预览图已保留，请重试')));
  }

  Future<void> _viewOriginal(String url) async {
    final index = _currentIndex;
    try {
      await _ensureOriginal(url);
      if (mounted && _currentIndex == index) {
        await _checkMotionPhotoForIndex(index);
      }
    } catch (_) {
      if (mounted) _showOriginalError();
    }
  }

  Widget _buildOriginalButton(String url) {
    final loading = _originalRequests.containsKey(url);
    final ready = _cache.isOriginalKnown(url);
    final bytes = _cache.mediaInfo(url)?.originalBytes ?? 0;
    final size = bytes >= 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).ceil()} KB';
    return TextButton(
      key: const ValueKey('view-original-button'),
      onPressed: loading || ready ? null : () => _viewOriginal(url),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white70,
        backgroundColor: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
      ),
      child: loading
          ? SizedBox(
              width: 112,
              height: 20,
              child: ImageDownloadPlaceholder(
                url: url,
                original: true,
                tracker: _cache.downloads,
                color: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            )
          : Text(
              ready ? '已加载原图' : '查看原图${bytes > 0 ? ' · $size' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
    );
  }

  Widget _buildLiveButton() {
    // 浏览已发布动态：原有轻点播放/暂停逻辑
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleLivePlayback,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _isPlaying ? Colors.white.withAlpha(220) : Colors.black54,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isPlaying ? Colors.white : Colors.white30,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying
                  ? Icons.motion_photos_on
                  : Icons.motion_photos_on_outlined,
              size: 15,
              color: _isPlaying ? Colors.black87 : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              '实况',
              style: TextStyle(
                color: _isPlaying ? Colors.black87 : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          key: const ValueKey('image-preview-canvas'),
          fit: StackFit.expand,
          children: [
            // 1. 底层：完整的 PhotoViewGallery（包含双指缩放、放大后拖动、边缘翻页手势，完全不破坏原有体验）
            PhotoViewGallery.builder(
              itemCount: _totalCount,
              builder: (context, index) => PhotoViewGalleryPageOptions(
                imageProvider: _getImageProvider(index),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4.0,
                onTapUp: (_, _, _) =>
                    setState(() => _controlsVisible = !_controlsVisible),
                gestureDetectorBehavior: HitTestBehavior.opaque,
                errorBuilder: (_, error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        size: 48,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              loadingBuilder: (context, _) {
                // Each gallery page has its own provider, including neighbors
                // loaded while swiping. Do not use the current page's URL here.
                final provider = context
                    .findAncestorWidgetOfExactType<PhotoView>()
                    ?.imageProvider;
                if (provider is CachedNetworkImageProvider) {
                  return ImageDownloadPlaceholder(
                    url: provider.url,
                    tracker: _cache.downloads,
                    color: Colors.white70,
                    backgroundColor: Colors.black,
                  );
                }
                return const Center(
                  child: Text(
                    '正在读取图片…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                );
              },
              pageController: _pageController,
              onPageChanged: _onPageChanged,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              gaplessPlayback: true,
            ),

            // 2. 视频层：仅在播放状态下贴合覆盖，通过 IgnorePointer 确保手势依然能透传，播完自动退出
            if (_isMotionPhoto &&
                _isPlaying &&
                _videoController != null &&
                _videoController!.value.isInitialized)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ImagePreviewChrome(
                visible: _controlsVisible,
                child: ImagePreviewGlass(
                  key: const ValueKey('image-preview-toolbar'),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          BackButton(color: Colors.white),
                          Expanded(
                            child: Text(
                              _totalCount > 1
                                  ? '${_currentIndex + 1} / $_totalCount'
                                  : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: _canDownload
                                ? IconButton(
                                    icon: _isDownloading
                                        ? SizedBox(
                                            width: 32,
                                            height: 24,
                                            child: _downloadingUrl != null
                                                ? ImageDownloadPlaceholder(
                                                    url: _downloadingUrl!,
                                                    original: true,
                                                    tracker: _cache.downloads,
                                                    color: Colors.white,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                  )
                                                : const FittedBox(
                                                    child: Text(
                                                      '保存中',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                          )
                                        : const Icon(
                                            Icons.download_rounded,
                                            color: Colors.white,
                                          ),
                                    tooltip: '下载',
                                    onPressed: _isDownloading
                                        ? null
                                        : _download,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 实况开关与顶栏一起隐藏，照片手势仍然由 PhotoView 处理。
            if (_showLiveButton)
              Positioned(
                left: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                child: ImagePreviewChrome(
                  visible: _controlsVisible,
                  child: _buildLiveButton(),
                ),
              ),
            if (_currentUrl != null && _cache.supportsPreviews(_currentUrl!))
              Positioned(
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                child: ImagePreviewChrome(
                  visible: _controlsVisible,
                  child: _buildOriginalButton(_currentUrl!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
