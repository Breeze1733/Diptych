import 'dart:async';

enum ImageDownloadPhase {
  queued,
  connecting,
  preparing,
  downloading,
  completed,
  failed,
}

class ImageDownloadProgress {
  const ImageDownloadProgress({
    required this.url,
    this.phase = ImageDownloadPhase.queued,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  final String url;
  final ImageDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    if (phase == ImageDownloadPhase.completed) return 1;
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  int? get percent {
    final value = fraction;
    if (value == null) return null;
    // Only report completion once the response stream actually finishes.
    return phase == ImageDownloadPhase.completed
        ? 100
        : (value * 100).floor().clamp(0, 99);
  }
}

/// Shares byte progress between background preloads and every image viewer.
class ImageDownloadTracker {
  final _states = <String, ImageDownloadProgress>{};
  final _changes = StreamController<ImageDownloadProgress>.broadcast();
  static const _retainedStates = 128;

  ImageDownloadProgress current(String url) =>
      _states[url] ?? ImageDownloadProgress(url: url);

  Stream<ImageDownloadProgress> watch(String url) =>
      _changes.stream.where((progress) => progress.url == url);

  void queue(String url) {
    final phase = _states[url]?.phase;
    if (phase == ImageDownloadPhase.queued ||
        phase == ImageDownloadPhase.connecting ||
        phase == ImageDownloadPhase.preparing ||
        phase == ImageDownloadPhase.downloading) {
      return;
    }
    _set(ImageDownloadProgress(url: url));
  }

  void start(String url) => _set(
    ImageDownloadProgress(url: url, phase: ImageDownloadPhase.connecting),
  );

  void preparing(String url) => _set(
    ImageDownloadProgress(url: url, phase: ImageDownloadPhase.preparing),
  );

  void update(String url, int receivedBytes, int? totalBytes) => _set(
    ImageDownloadProgress(
      url: url,
      phase: ImageDownloadPhase.downloading,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
    ),
  );

  void complete(String url) => _finish(url, ImageDownloadPhase.completed);

  void fail(String url) => _finish(url, ImageDownloadPhase.failed);

  void _finish(String url, ImageDownloadPhase phase) {
    final previous = current(url);
    _set(
      ImageDownloadProgress(
        url: url,
        phase: phase,
        receivedBytes: previous.receivedBytes,
        totalBytes: previous.totalBytes,
      ),
    );
  }

  void _set(ImageDownloadProgress progress) {
    final previous = _states[progress.url];
    _states[progress.url] = progress;
    if (previous == null ||
        previous.phase != progress.phase ||
        previous.percent != progress.percent ||
        previous.totalBytes != progress.totalBytes ||
        (progress.percent == null &&
            previous.receivedBytes ~/ 65536 !=
                progress.receivedBytes ~/ 65536)) {
      _changes.add(progress);
    }
    // Keep live requests, but bound the history retained for decoding/caching.
    if (_states.length > _retainedStates) {
      final finished = _states.entries
          .where(
            (entry) =>
                entry.value.phase == ImageDownloadPhase.completed ||
                entry.value.phase == ImageDownloadPhase.failed,
          )
          .map((entry) => entry.key)
          .take(_states.length - _retainedStates)
          .toList();
      finished.forEach(_states.remove);
    }
  }

  Future<void> dispose() => _changes.close();
}
