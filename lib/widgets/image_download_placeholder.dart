import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../services/image_download_progress.dart';
import '../services/private_image_cache.dart';

/// Uses the actual transfer state, including preloads started off-screen.
class ImageDownloadPlaceholder extends StatelessWidget {
  const ImageDownloadPlaceholder({
    super.key,
    required this.url,
    this.color = AppTheme.textSecondary,
    this.backgroundColor = AppTheme.softSurface,
    this.tracker,
    this.original = false,
  });

  final String url;
  final Color color;
  final Color backgroundColor;
  final ImageDownloadTracker? tracker;
  final bool original;

  @override
  Widget build(BuildContext context) {
    final downloads = tracker ?? PrivateImageCache().downloads;
    final trackedUrl = original ? 'original:$url' : url;
    return StreamBuilder<ImageDownloadProgress>(
      stream: downloads.watch(trackedUrl),
      initialData: downloads.current(trackedUrl),
      builder: (context, snapshot) {
        // Reading current also covers a transfer that advanced before listening.
        final progress = downloads.current(trackedUrl);
        final percent = progress.percent;
        final label = switch (progress.phase) {
          ImageDownloadPhase.queued => '排队中',
          ImageDownloadPhase.connecting => '连接中',
          ImageDownloadPhase.preparing => '正在生成预览',
          ImageDownloadPhase.completed => '100%',
          ImageDownloadPhase.failed => '加载失败',
          ImageDownloadPhase.downloading =>
            percent != null
                ? '$percent%'
                : '已下载 ${_formatBytes(progress.receivedBytes)}',
        };
        return ColoredBox(
          color: backgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 72 || constraints.maxHeight < 56;
              final text = FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
              if (compact) {
                return Center(
                  child: Padding(padding: const EdgeInsets.all(2), child: text),
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      text,
                      if (percent != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 96,
                          child: LinearProgressIndicator(
                            value: percent / 100,
                            minHeight: 3,
                            color: color,
                            backgroundColor: color.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
