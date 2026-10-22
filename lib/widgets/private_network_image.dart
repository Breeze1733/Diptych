import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/private_image_cache.dart';

/// Refreshes decoded pixels when the same photo's cache upgrades to original.
class PrivateNetworkImage extends StatelessWidget {
  const PrivateNetworkImage({
    super.key,
    required this.imageUrl,
    this.usePreview = false,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });
  final String imageUrl;

  /// Only diary photo widgets opt into previews. Profile images use originals.
  final bool usePreview;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  @override
  Widget build(BuildContext context) {
    final cache = PrivateImageCache();
    return StreamBuilder<String>(
      stream: cache.changes.where((url) => url.isEmpty || url == imageUrl),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final targetWidth = width ?? constraints.maxWidth;
          final targetHeight = height ?? constraints.maxHeight;
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final info = cache.mediaInfo(imageUrl);
          int? decodeWidth;
          if (targetWidth.isFinite && targetWidth > 0) {
            var pixels = targetWidth * ratio;
            if (info != null &&
                info.width > 0 &&
                info.height > 0 &&
                targetHeight.isFinite &&
                targetHeight > 0 &&
                fit == BoxFit.cover) {
              final fromHeight =
                  targetHeight * ratio * info.width / info.height;
              if (fromHeight > pixels) pixels = fromHeight;
            }
            decodeWidth = pixels.ceil();
          }
          return CachedNetworkImage(
            cacheManager: cache,
            imageUrl: imageUrl,
            cacheKey: usePreview
                ? cache.displayKey(imageUrl)
                : cache.originalDisplayKey(imageUrl),
            width: width,
            height: height,
            memCacheWidth: decodeWidth,
            fit: fit,
            useOldImageOnUrlChange: true,
            placeholder: placeholder,
            errorWidget: errorWidget,
          );
        },
      ),
    );
  }
}
