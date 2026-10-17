import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 原生 CPU 锁通道；业务任务统一通过 TransferKeepAlive 持有租约。
class WakelockHelper {
  WakelockHelper._();

  static const _channel = MethodChannel(
    'com.splitmoments.split_moments/wakelock',
  );

  /// 申请 CPU 唤醒锁
  ///
  /// [timeout] 默认 10 分钟，由租约管理器在任务存活期间定期续租。
  /// 即使意外崩溃未调用 release，Android 系统也会在达到超时后自动释放，避免过度耗电。
  static Future<bool> acquire({
    Duration timeout = const Duration(minutes: 10),
  }) async {
    try {
      await _channel
          .invokeMethod<void>('acquire', {'timeoutMs': timeout.inMilliseconds})
          .timeout(const Duration(seconds: 5));
      debugPrint(
        '[WakelockHelper] CPU WakeLock acquired (timeout: ${timeout.inSeconds}s)',
      );
      return true;
    } catch (e) {
      debugPrint('[WakelockHelper] Failed to acquire WakeLock: $e');
      return false;
    }
  }

  /// 释放 CPU 唤醒锁（必须在 finally 块中调用）
  static Future<bool> release() async {
    try {
      await _channel
          .invokeMethod<void>('release')
          .timeout(const Duration(seconds: 5));
      debugPrint('[WakelockHelper] CPU WakeLock released');
      return true;
    } catch (e) {
      debugPrint('[WakelockHelper] Failed to release WakeLock: $e');
      return false;
    }
  }
}
