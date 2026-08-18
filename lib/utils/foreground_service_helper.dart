import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 前台保活服务辅助类：在 APK 下载与多图发布期间挂起系统通知栏前台服务，
/// 获取 Android Linux 内核最高网络白名单，100% 防止切后台时被系统掐断网络连接。
class ForegroundServiceHelper {
  ForegroundServiceHelper._();

  static const _channel = MethodChannel('com.splitmoments.split_moments/foreground_service');

  /// 启动前台保活服务并在状态栏显示通知
  static Future<void> start({
    required String title,
    required String content,
    int maxProgress = 0,
    int progress = 0,
  }) async {
    try {
      await _channel.invokeMethod('start', {
        'title': title,
        'content': content,
        'maxProgress': maxProgress,
        'progress': progress,
      });
      debugPrint('[ForegroundService] Started: $title - $content');
    } catch (e) {
      debugPrint('[ForegroundService] Failed to start: $e');
    }
  }

  /// 更新通知栏中的进度
  static Future<void> update({
    required String title,
    required String content,
    int maxProgress = 0,
    int progress = 0,
  }) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'content': content,
        'maxProgress': maxProgress,
        'progress': progress,
      });
    } catch (_) {}
  }

  /// 停止前台服务并清除通知
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      debugPrint('[ForegroundService] Stopped');
    } catch (e) {
      debugPrint('[ForegroundService] Failed to stop: $e');
    }
  }
}
