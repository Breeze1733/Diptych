import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 原生前台服务通道；业务任务统一通过 TransferKeepAlive 持有租约。
class ForegroundServiceHelper {
  ForegroundServiceHelper._();

  static const _channel = MethodChannel(
    'com.splitmoments.split_moments/foreground_service',
  );

  /// 启动前台保活服务并在状态栏显示通知
  static Future<bool> start({
    required String title,
    required String content,
    int maxProgress = 0,
    int progress = 0,
  }) async {
    try {
      await _channel
          .invokeMethod<void>('start', {
            'title': title,
            'content': content,
            'maxProgress': maxProgress,
            'progress': progress,
          })
          .timeout(const Duration(seconds: 5));
      debugPrint('[ForegroundService] Start accepted: $title - $content');
      return true;
    } catch (e) {
      debugPrint('[ForegroundService] Failed to start: $e');
      return false;
    }
  }

  /// 更新通知栏中的进度
  static Future<bool> update({
    required String title,
    required String content,
    int maxProgress = 0,
    int progress = 0,
  }) async {
    try {
      await _channel
          .invokeMethod<void>('update', {
            'title': title,
            'content': content,
            'maxProgress': maxProgress,
            'progress': progress,
          })
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('[ForegroundService] Failed to update: $e');
      return false;
    }
  }

  /// 停止前台服务并清除通知
  static Future<bool> stop() async {
    try {
      await _channel
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 5));
      debugPrint('[ForegroundService] Stopped');
      return true;
    } catch (e) {
      debugPrint('[ForegroundService] Failed to stop: $e');
      return false;
    }
  }
}
