import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/foreground_service_helper.dart';
import '../utils/wakelock_helper.dart';

typedef _NotificationState = ({
  String title,
  String content,
  int maxProgress,
  int progress,
});

/// Coordinates Android's shared transfer service and CPU lock across tasks.
/// Each task owns a lease and releases it in its own finally block.
class TransferKeepAlive {
  TransferKeepAlive._();

  static const _wakeLockTimeout = Duration(minutes: 10);
  static final _leases = <TransferKeepAliveLease>{};
  static Future<void> _pending = Future<void>.value();
  static Timer? _renewal;
  static Timer? _retry;
  static int _retryAttempts = 0;
  static bool _wakeLockActive = false;
  static bool _wakeLockMayBeActive = false;
  static bool _foregroundMayBeActive = false;
  static _NotificationState? _notification;

  /// Omitting [title] requests only a CPU lock, without a notification.
  static Future<TransferKeepAliveLease> acquire({
    String? title,
    String content = '',
    int maxProgress = 0,
    int progress = 0,
  }) async {
    final lease = TransferKeepAliveLease._(
      title,
      content,
      maxProgress,
      progress,
    );
    await _enqueue(() async {
      _leases.add(lease);
      await _reconcile();
    });
    return lease;
  }

  // Serialize state changes as well as native calls. A failed platform call
  // must never poison the queue or make the transfer itself fail.
  static Future<void> _enqueue(Future<void> Function() operation) {
    _pending = _pending.then((_) => operation()).catchError((Object error) {
      debugPrint('[TransferKeepAlive] Coordination failed: $error');
    });
    return _pending;
  }

  static Future<void> _reconcile({
    bool renewWakeLock = false,
    bool isRetry = false,
  }) async {
    if (!isRetry) {
      _retry?.cancel();
      _retry = null;
      _retryAttempts = 0;
    }

    if (_leases.isEmpty) {
      _renewal?.cancel();
      _renewal = null;
    } else {
      // Native timeout limits battery use if Dart stops running. Keep it fresh
      // while a live task still owns a lease, including very long transfers.
      _renewal ??= Timer.periodic(const Duration(minutes: 5), (_) {
        unawaited(_enqueue(() => _reconcile(renewWakeLock: true)));
      });
    }

    var failed = false;
    final visible = _leases.where((lease) => lease._title != null).toList();
    if (visible.isEmpty) {
      if (_foregroundMayBeActive) {
        if (await ForegroundServiceHelper.stop()) {
          _notification = null;
          _foregroundMayBeActive = false;
        } else {
          failed = true;
        }
      }
    } else {
      // Retain the oldest task's notification until it finishes. Other tasks
      // retain their own progress so their notification can take over later.
      final owner = visible.first;
      final state = (
        title: owner._title!,
        content: visible.length == 1
            ? owner._content
            : '${owner._content} · 另有 ${visible.length - 1} 个传输任务',
        maxProgress: owner._maxProgress,
        progress: owner._progress,
      );
      if (state != _notification) {
        // A timed-out channel call may still have reached Android. Remember
        // that possibility so the last lease always sends a cleanup request.
        _foregroundMayBeActive = true;
        final accepted = _notification == null
            ? await ForegroundServiceHelper.start(
                title: state.title,
                content: state.content,
                maxProgress: state.maxProgress,
                progress: state.progress,
              )
            : await ForegroundServiceHelper.update(
                title: state.title,
                content: state.content,
                maxProgress: state.maxProgress,
                progress: state.progress,
              );
        if (accepted) {
          _notification = state;
        } else {
          failed = true;
        }
      }
    }

    if (_leases.isEmpty) {
      if (_wakeLockMayBeActive) {
        if (await WakelockHelper.release()) {
          _wakeLockActive = false;
          _wakeLockMayBeActive = false;
        } else {
          failed = true;
        }
      }
    } else if (!_wakeLockActive || renewWakeLock) {
      _wakeLockMayBeActive = true;
      if (await WakelockHelper.acquire(timeout: _wakeLockTimeout)) {
        _wakeLockActive = true;
      } else {
        failed = true;
      }
    }

    // Retry transient start/stop failures without holding up a user action.
    if (failed && _retryAttempts < 3) {
      _retryAttempts++;
      _retry = Timer(const Duration(seconds: 2), () {
        _retry = null;
        unawaited(_enqueue(() => _reconcile(isRetry: true)));
      });
    }
  }
}

class TransferKeepAliveLease {
  TransferKeepAliveLease._(
    this._title,
    this._content,
    this._maxProgress,
    this._progress,
  );

  String? _title;
  String _content;
  int _maxProgress;
  int _progress;
  bool _released = false;
  Future<void>? _releaseFuture;

  Future<void> update({
    String? title,
    String? content,
    int? maxProgress,
    int? progress,
  }) {
    if (_released) return Future<void>.value();
    return TransferKeepAlive._enqueue(() async {
      if (_released) return;
      _title = title ?? _title;
      _content = content ?? _content;
      _maxProgress = maxProgress ?? _maxProgress;
      _progress = progress ?? _progress;
      await TransferKeepAlive._reconcile();
    });
  }

  /// Safe to invoke repeatedly, including from both dispose and finally.
  Future<void> release() {
    if (_released) return _releaseFuture ?? Future<void>.value();
    _released = true;
    return _releaseFuture = TransferKeepAlive._enqueue(() async {
      TransferKeepAlive._leases.remove(this);
      await TransferKeepAlive._reconcile();
    });
  }
}
