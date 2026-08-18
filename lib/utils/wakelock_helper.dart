import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// CPU 唤醒锁辅助类：在后台长耗时上传/下载时防止手机进入深度休眠切断网络连接
class WakelockHelper {
  WakelockHelper._();

  static const _channel = MethodChannel('com.splitmoments.split_moments/wakelock');

  /// 申请 CPU 唤醒锁
  ///
  /// [timeout] 默认 10 分钟（600,000 毫秒），足够多张超高清大图或弱网环境下平稳传完。
  /// 即使意外崩溃未调用 release，Android 系统也会在达到超时后自动释放，避免过度耗电。
  static Future<void> acquire({Duration timeout = const Duration(minutes: 10)}) async {
    try {
      await _channel.invokeMethod('acquire', {
        'timeoutMs': timeout.inMilliseconds,
      });
      debugPrint('[WakelockHelper] CPU WakeLock acquired (timeout: ${timeout.inSeconds}s)');
    } catch (e) {
      debugPrint('[WakelockHelper] Failed to acquire WakeLock: $e');
    }
  }

  /// 释放 CPU 唤醒锁（必须在 finally 块中调用）
  static Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
      debugPrint('[WakelockHelper] CPU WakeLock released');
    } catch (e) {
      debugPrint('[WakelockHelper] Failed to release WakeLock: $e');
    }
  }

  /// 检查当前是否持有锁
  static Future<bool> isHeld() async {
    try {
      final held = await _channel.invokeMethod<bool>('isHeld');
      return held ?? false;
    } catch (_) {
      return false;
    }
  }
}
