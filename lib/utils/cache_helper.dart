import 'dart:io';
import 'package:flutter/painting.dart' show imageCache;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 缓存管理工具：计算缓存大小 + 清理缓存
class CacheHelper {
  CacheHelper._();

  // SharedPreferences 中以这些前缀开头的 key 视为缓存
  static const _cacheKeyPrefixes = [
    'cache_day_',
    'cache_marked_',
    'cache_user_',
    'cache_all_dates_',
  ];

  /// 计算各来源缓存大小（字节），返回分类明细
  static Future<Map<String, int>> getCacheSizeDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final tempDir = await getTemporaryDirectory();

    final results = await Future.wait([
      _getPrefsCacheSize(prefs),
      _getDirSize(tempDir),
    ]);

    return {
      '日记/用户缓存': results[0],
      '图片缓存(temp)': results[1],
    };
  }

  /// 计算总缓存大小
  static Future<int> getTotalCacheSize() async {
    final details = await getCacheSizeDetails();
    int total = 0;
    for (final v in details.values) {
      total += v;
    }
    return total;
  }

  /// 清理所有缓存，返回释放的字节数
  static Future<int> clearAllCache() async {
    final before = await getTotalCacheSize();

    // 1. SharedPreferences 缓存
    await _clearPrefsCache();

    // 2. 网络图片缓存（cached_network_image 使用的 DefaultCacheManager）
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}

    // 3. Flutter 内存图片缓存
    imageCache.clear();
    imageCache.clearLiveImages();

    // 4. 临时目录
    await _clearDirContents(await getTemporaryDirectory());

    final after = await getTotalCacheSize();
    return before - after;
  }

  /// 格式化字节为可读字符串
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ─── 私有辅助 ───

  static Future<int> _getPrefsCacheSize(SharedPreferences prefs) async {
    int size = 0;
    for (final key in prefs.getKeys()) {
      if (_cacheKeyPrefixes.any((p) => key.startsWith(p))) {
        size += (prefs.getString(key)?.length ?? 0);
      }
    }
    return size;
  }

  static Future<void> _clearPrefsCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (_cacheKeyPrefixes.any((p) => key.startsWith(p))) {
        await prefs.remove(key);
      }
    }
  }

  /// 递归计算目录大小
  static Future<int> _getDirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }

  /// 清空目录内容（保留目录本身）
  static Future<void> _clearDirContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
