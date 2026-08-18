import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_config.dart';

/// 版本信息
class VersionInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String releaseNotes;

  const VersionInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.releaseNotes = '',
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      version: json['version'] as String? ?? '0.0.0',
      versionCode: json['version_code'] as int? ?? 0,
      downloadUrl: json['download_url'] as String? ?? '',
      releaseNotes: json['release_notes'] as String? ?? '',
    );
  }
}

/// 系统下载任务状态
class DownloadTaskStatus {
  final String status; // 'running', 'successful', 'failed', 'paused', 'pending', 'unknown'
  final int downloadedBytes;
  final int totalBytes;
  final String? filePath;

  const DownloadTaskStatus({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.filePath,
  });

  double get progress => (totalBytes > 0) ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  bool get isSuccessful => status == 'successful';
  bool get isFailed => status == 'failed';
  bool get isRunning => status == 'running' || status == 'pending' || status == 'paused';
}

/// 更新检测与 Android 系统级 DownloadManager 安装服务
class UpdateService {
  static const String baseUrl = ApiConfig.apiBaseUrl;
  static const _downloaderChannel = MethodChannel('com.splitmoments.split_moments/downloader');
  static const _keyPendingCleanupId = 'pending_apk_cleanup_id';
  static const _keyPendingCleanupPath = 'pending_apk_cleanup_path';

  final http.Client _client = http.Client();

  dynamic _safeDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      final preview = body.length > 200 ? '${body.substring(0, 200)}...' : body;
      throw Exception('服务器返回非 JSON: $preview');
    }
  }

  /// 获取当前应用版本
  Future<PackageInfo> getCurrentVersion() => PackageInfo.fromPlatform();

  /// 检查远程最新版本
  Future<VersionInfo> checkLatestVersion() async {
    final res = await _client.get(Uri.parse('$baseUrl/version/latest'));
    if (res.statusCode != 200) {
      throw Exception('获取版本信息失败 (${res.statusCode})');
    }
    final body = _safeDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception('版本接口响应异常');
    }
    return VersionInfo.fromJson(body['data']);
  }

  /// 是否需要更新
  bool needUpdate(PackageInfo current, VersionInfo latest) {
    final curCode = int.tryParse(current.buildNumber) ?? 0;
    return latest.versionCode > curCode;
  }

  /// 通过 Android 系统 DownloadManager 发起系统级后台下载
  /// 状态栏自动显示下载通知与进度，切后台、锁屏、甚至关闭 App 都能在后台稳步下载
  Future<int> startSystemDownload(String url, {String? version}) async {
    final title = 'Diptych 新版本${version != null ? ' $version' : ''}';
    const desc = '正在下载更新安装包，切后台不受影响...';
    final result = await _downloaderChannel.invokeMethod<int>('startDownload', {
      'url': url,
      'title': title,
      'description': desc,
      'fileName': 'diptych_update.apk',
    });
    return result ?? 0;
  }

  /// 查询系统 DownloadManager 下载进度与状态
  Future<DownloadTaskStatus> getSystemDownloadStatus(int downloadId) async {
    final result = await _downloaderChannel.invokeMapMethod<String, dynamic>(
      'getDownloadStatus',
      {'downloadId': downloadId},
    );
    if (result == null) {
      return const DownloadTaskStatus(status: 'unknown', downloadedBytes: 0, totalBytes: 0);
    }
    return DownloadTaskStatus(
      status: result['status']?.toString() ?? 'unknown',
      downloadedBytes: (result['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (result['totalBytes'] as num?)?.toInt() ?? 0,
      filePath: result['filePath']?.toString(),
    );
  }

  /// 移除/取消系统下载记录并物理删除已下载的临时文件
  Future<void> removeSystemDownload(int downloadId) async {
    try {
      await _downloaderChannel.invokeMethod('removeDownload', {'downloadId': downloadId});
    } catch (_) {}
  }

  /// 调起系统安装 APK
  Future<void> installApk(String filePath) async {
    try {
      await _downloaderChannel.invokeMethod('installApk', {'filePath': filePath});
    } catch (_) {
      // 备用 fallback
      await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
    }
  }

  /// 标记待清理的下载 ID 和物理文件路径（下次启动时彻底清除）
  Future<void> markForCleanup(int downloadId, String? filePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPendingCleanupId, downloadId);
    if (filePath != null && filePath.isNotEmpty) {
      await prefs.setString(_keyPendingCleanupPath, filePath);
    }
  }

  /// 启动时清理上次更新的安装包（多重防线，确保 100% 成功清理释放空间）
  static Future<void> cleanupOldApk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingId = prefs.getInt(_keyPendingCleanupId);
      final pendingPath = prefs.getString(_keyPendingCleanupPath);

      // 防线 1：通知系统 DownloadManager 移除记录并清理文件
      if (pendingId != null && pendingId > 0) {
        try {
          await _downloaderChannel.invokeMethod('removeDownload', {'downloadId': pendingId});
        } catch (_) {}
        await prefs.remove(_keyPendingCleanupId);
      }

      // 防线 2：根据记录的具体路径直接文件删除
      if (pendingPath != null) {
        try {
          final file = File(pendingPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        await prefs.remove(_keyPendingCleanupPath);
      }

      // 防线 3：遍历应用外部存储 Download 目录与 Cache 目录下的全部 *.apk 兜底删除
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final downloadDir = Directory('${extDir.path}/Download');
          if (await downloadDir.exists()) {
            await for (final entity in downloadDir.list()) {
              if (entity is File && entity.path.endsWith('.apk')) {
                try { await entity.delete(); } catch (_) {}
              }
            }
          }
          final rootApk = File('${extDir.path}/diptych_update.apk');
          if (await rootApk.exists()) {
            try { await rootApk.delete(); } catch (_) {}
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  void dispose() {
    _client.close();
  }
}
