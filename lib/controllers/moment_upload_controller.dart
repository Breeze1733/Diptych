import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';
import '../services/transfer_keep_alive.dart';
import '../widgets/photo_grid_picker.dart';

/// 编辑器的图片传输队列。照片排序和文字由页面持有，网络任务独立管理。
class MomentUploadController extends ChangeNotifier {
  final StorageService storage;
  final String folder;
  final List<PhotoEntry> Function() photos;
  final VoidCallback onUploaded;
  final uploadedUrls = <String, String>{};
  final uploadedIsLive = <String, bool>{};
  final statuses = <String, PhotoUploadStatus>{};
  final progress = <String, double>{};
  final _pending = <String>[];
  final _inFlight = <String, _UploadJob>{};
  final _deletes = <String>[];
  final Set<String> _committedUrls;
  bool _deleting = false;
  bool _publishing = false;
  bool _disposed = false;
  TransferKeepAliveLease? _lease;
  Future<void> _keepAliveWork = Future.value();

  MomentUploadController({
    required this.storage,
    required this.folder,
    required this.photos,
    required this.onUploaded,
    Iterable<String> committedUrls = const [],
  }) : _committedUrls = committedUrls.toSet();

  void setCommittedUrls(Iterable<String> urls) {
    _committedUrls
      ..clear()
      ..addAll(urls);
  }

  bool get isUploading => _pending.isNotEmpty || _inFlight.isNotEmpty;

  void restore(String path, String url, bool isLive) {
    uploadedUrls[path] = url;
    uploadedIsLive[path] = isLive;
    statuses[path] = PhotoUploadStatus.success;
  }

  void enqueue(Iterable<PhotoEntry> entries) {
    if (_disposed) return;
    for (final entry in entries) {
      if (!entry.isLocal || entry.file == null) continue;
      final path = entry.file!.path;
      if (uploadedUrls.containsKey(path) ||
          _pending.contains(path) ||
          _inFlight.containsKey(path)) {
        continue;
      }
      _pending.add(path);
      statuses[path] = PhotoUploadStatus.queued;
    }
    _changed();
    _pump();
  }

  void remove(PhotoEntry entry) {
    if (!entry.isLocal || entry.file == null) return;
    final path = entry.file!.path;
    _pending.remove(path);
    final job = _inFlight[path];
    if (job != null) {
      job.cancelled = true;
      final id = job.uploadId;
      if (id != null) unawaited(storage.abortUpload(id));
    }
    final url = uploadedUrls.remove(path);
    if (url != null) deleteOrphan(url);
    uploadedIsLive.remove(path);
    statuses.remove(path);
    progress.remove(path);
    _changed();
  }

  void cancelUploads() {
    _pending.clear();
    for (final job in _inFlight.values) {
      job.cancelled = true;
      final id = job.uploadId;
      if (id != null) unawaited(storage.abortUpload(id));
    }
    _changed();
  }

  void setPublishing(bool value) {
    _publishing = value;
    _changed();
  }

  Future<void> waitForUploads() async {
    while (isUploading && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _pump() {
    if (_disposed || _inFlight.isNotEmpty || _pending.isEmpty) return;
    final path = _pending.removeAt(0);
    final entry = photos()
        .where((p) => p.isLocal && p.file?.path == path)
        .firstOrNull;
    if (entry == null) {
      _pump();
      return;
    }
    final job = _UploadJob();
    _inFlight[path] = job;
    statuses[path] = PhotoUploadStatus.uploading;
    progress[path] = 0;
    _changed();
    unawaited(_upload(entry, job));
  }

  Future<void> _upload(PhotoEntry entry, _UploadJob job) async {
    final file = entry.file!;
    final path = file.path;
    try {
      final url = await storage.uploadImage(
        file,
        folder,
        onProgress: (value) {
          if (_disposed || job.cancelled) return;
          progress[path] = value;
          _changed();
        },
        isCancelled: () => _disposed || job.cancelled,
        onUploadIdCreated: (id) {
          job.uploadId = id;
          if (_disposed || job.cancelled) unawaited(storage.abortUpload(id));
        },
      );
      if (_disposed || job.cancelled) {
        deleteOrphan(url);
      } else {
        restore(path, url, entry.isMotion && entry.uploadLive);
        onUploaded();
      }
    } on UploadCancelledException {
      statuses.remove(path);
    } catch (error) {
      if (!job.cancelled && !_disposed) {
        statuses[path] = PhotoUploadStatus.failed;
        debugPrint('[MomentUpload] 上传失败: $error');
      }
    } finally {
      _inFlight.remove(path);
      progress.remove(path);
      _changed();
      _pump();
    }
  }

  void deleteOrphan(String url) {
    if (url.isEmpty || _deletes.contains(url) || _committedUrls.contains(url)) {
      return;
    }
    _deletes.add(url);
    unawaited(_deleteNext());
  }

  Future<void> _deleteNext() async {
    if (_deleting) return;
    _deleting = true;
    _changed();
    try {
      while (_deletes.isNotEmpty) {
        final url = _deletes.removeAt(0);
        try {
          await storage.deleteImage(url);
        } catch (error) {
          debugPrint('[MomentUpload] 清理未使用图片失败: $error');
        }
      }
    } finally {
      _deleting = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
    // 将 acquire/update/release 排队，避免 acquire 未完成时 dispose 导致锁泄漏。
    _keepAliveWork = _keepAliveWork
        .then((_) async {
          final busy = isUploading || _deleting || _publishing;
          if (!busy || _disposed) {
            final lease = _lease;
            _lease = null;
            await lease?.release();
            return;
          }
          final all = photos().where((p) => p.isLocal).toList();
          final done = all
              .where((p) => uploadedUrls.containsKey(p.file?.path))
              .length;
          final content = _publishing
              ? '正在发布日记...'
              : _deleting
              ? '正在清理图片...'
              : '正在上传照片 ($done/${all.length})...';
          _lease ??= await TransferKeepAlive.acquire(
            title: 'Diptych 图片同步',
            content: content,
            maxProgress: all.isEmpty ? 1 : all.length,
            progress: done,
          );
          if (_disposed) {
            await _lease?.release();
            _lease = null;
          } else {
            await _lease?.update(
              content: content,
              maxProgress: all.isEmpty ? 1 : all.length,
              progress: done,
            );
          }
        })
        .catchError((Object error) {
          debugPrint('[MomentUpload] 更新保活状态失败: $error');
        });
  }

  @override
  void dispose() {
    cancelUploads();
    _disposed = true;
    _publishing = false;
    _changed();
    super.dispose();
  }
}

class _UploadJob {
  bool cancelled = false;
  String? uploadId;
}
