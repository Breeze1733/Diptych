import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 文件保存工具
class FileHelper {
  static const _channel = MethodChannel('com.splitmoments.split_moments/media_scanner');

  FileHelper._();

  /// 获取设备的 Downloads 目录
  /// Android: /storage/emulated/0/Download/
  /// iOS: 回退到应用文档目录
  static Future<Directory> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        // extDir.path 示例: /storage/emulated/0/Android/data/com.example.app/files
        // 截取 Android 之前的部分，拼接 Download
        final path = extDir.path;
        final androidIndex = path.indexOf('Android');
        if (androidIndex > 0) {
          final rootPath = path.substring(0, androidIndex);
          final downloadsDir = Directory('${rootPath}Download');
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          return downloadsDir;
        }
      }
    }
    // iOS 或回退：使用应用文档目录
    return getApplicationDocumentsDirectory();
  }

  /// 通知系统扫描文件，使其出现在相册/文件管理器中
  static Future<void> scanFile(String path) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scanFile', {'path': path});
      } catch (_) {
        // 扫描失败不影响主流程
      }
    }
  }

  /// 将应用私有文档目录中的旧图片迁移到 Downloads 目录
  /// 返回迁移成功的文件数量
  static Future<int> migrateToDownloads() async {
    final sourceDir = await getApplicationDocumentsDirectory();
    final targetDir = await getDownloadsDirectory();
    int count = 0;

    if (!await sourceDir.exists()) return 0;

    final files = sourceDir.listSync().whereType<File>();
    for (final file in files) {
      try {
        final targetFile = File('${targetDir.path}/${file.uri.pathSegments.last}');
        // 如果目标已存在则跳过
        if (await targetFile.exists()) continue;
        await file.copy(targetFile.path);
        await scanFile(targetFile.path);
        count++;
      } catch (_) {
        // 单个文件失败不影响其他文件
      }
    }
    return count;
  }
}
