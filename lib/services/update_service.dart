import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_config.dart';
import 'api_http_client.dart';
import 'auth_session.dart';
import 'http_request.dart';
import 'transfer_keep_alive.dart';

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

/// 更新检测与全速安装服务（带 CPU WakeLock 保活与启动自动清理）
class UpdateService {
  static const String baseUrl = ApiConfig.apiBaseUrl;
  static const _downloaderChannel = MethodChannel(
    'com.splitmoments.split_moments/downloader',
  );
  static const _keyPendingCleanupPath = 'pending_apk_cleanup_path';

  final Set<http.Client> _activeClients = {};
  final _sessionRevision = AuthSession.revision;
  bool _disposed = false;

  http.Client _createClient() {
    if (_disposed) throw StateError('更新服务已关闭');
    AuthSession.ensureRevision(_sessionRevision);
    final client = ApiHttpClient.create();
    _activeClients.add(client);
    return client;
  }

  Future<T> _request<T>(Future<T> Function(http.Client) request) async {
    final client = _createClient();
    try {
      return await runHttpRequest(
        request,
        clientFactory: () => client,
        sessionRevision: _sessionRevision,
      );
    } finally {
      _activeClients.remove(client);
    }
  }

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
    final res = await _request(
      (client) => client.get(Uri.parse('$baseUrl/version/latest')),
    );
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

  /// 全速直连流式下载 APK（支持 Foreground Service 前台保活 + HTTP Range 断点续传 + 10 分钟 WakeLock）
  Future<String> downloadApk(
    String url, {
    void Function(double progress, int downloadedBytes, int totalBytes)?
    onProgress,
  }) async {
    final lease = await TransferKeepAlive.acquire(
      title: 'Diptych 新版本下载',
      content: '正在全速下载安装包...',
      maxProgress: 100,
      progress: 0,
    );

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception('无法访问存储目录');

      final file = File('${dir.path}/diptych_update.apk');

      // 预先探测文件总大小
      var total = 0;
      try {
        final headRes = await _request((client) => client.head(Uri.parse(url)));
        if (headRes.statusCode == 200) {
          total = int.tryParse(headRes.headers['content-length'] ?? '') ?? 0;
        }
      } catch (_) {}

      // 如果有残留旧文件先清理
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      var downloaded = 0;
      int retryCount = 0;
      const maxRetries = 15; // 允许在极端网络抖动时自动无感重连 15 次
      String? validator;

      while (true) {
        IOSink? sink;
        http.Client? streamClient;
        try {
          streamClient = _createClient();
          final request = http.Request('GET', Uri.parse(url));
          request.headers['Accept-Encoding'] = 'identity';
          if (downloaded > 0) {
            request.headers['Range'] = 'bytes=$downloaded-';
            if (validator != null) request.headers['If-Range'] = validator;
          }

          final activeClient = streamClient;
          final streamed = await activeClient
              .send(request)
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () {
                  activeClient.close();
                  throw TimeoutException('等待下载响应超时');
                },
              );
          if (streamed.statusCode != 200 && streamed.statusCode != 206) {
            throw Exception('下载失败，服务器返回 ${streamed.statusCode}');
          }

          final isAppend = streamed.statusCode == 206 && downloaded > 0;
          int? expectedResponseBytes;
          if (streamed.statusCode == 206) {
            final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
                .firstMatch(streamed.headers['content-range'] ?? '');
            if (match == null) throw Exception('服务器未返回有效的下载范围');
            final start = int.parse(match[1]!);
            final end = int.parse(match[2]!);
            final rangeTotal = int.parse(match[3]!);
            if (start != downloaded ||
                end < start ||
                end >= rangeTotal ||
                (downloaded > 0 && total > 0 && total != rangeTotal)) {
              throw Exception('服务器返回的下载范围与本地文件不一致');
            }
            expectedResponseBytes = end - start + 1;
            if (streamed.contentLength != null &&
                streamed.contentLength != expectedResponseBytes) {
              throw Exception('下载范围与响应长度不一致');
            }
            total = rangeTotal;
          } else {
            // 完整响应是权威版本；Range 被忽略或 If-Range 失效时从头写入。
            downloaded = 0;
            expectedResponseBytes = streamed.contentLength;
            total = streamed.contentLength ?? total;
          }
          validator =
              streamed.headers['etag'] ?? streamed.headers['last-modified'];

          sink = file.openWrite(
            mode: isAppend ? FileMode.append : FileMode.write,
          );
          var responseBytes = 0;
          final timedStream = streamed.stream.timeout(
            const Duration(seconds: 30),
            onTimeout: (eventSink) {
              activeClient.close();
              eventSink.addError(TimeoutException('下载数据接收超时'));
              eventSink.close();
            },
          );
          await for (final chunk in timedStream) {
            responseBytes += chunk.length;
            downloaded += chunk.length;
            if ((expectedResponseBytes != null &&
                    responseBytes > expectedResponseBytes) ||
                (total > 0 && downloaded > total)) {
              throw Exception('下载内容超过服务器声明的长度');
            }
            sink.add(chunk);
            if (total > 0) {
              final percent = downloaded / total;
              if (onProgress != null) {
                onProgress(percent.clamp(0.0, 1.0), downloaded, total);
              }
              final downloadedMB = (downloaded / (1024 * 1024)).toStringAsFixed(
                1,
              );
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              final percentInt = (percent * 100).toInt().clamp(0, 100);
              lease.update(
                title: 'Diptych 新版本下载',
                content: '正在下载 $percentInt% ($downloadedMB MB / $totalMB MB)',
                maxProgress: 100,
                progress: percentInt,
              );
            }
          }

          await sink.flush();
          await sink.close();
          sink = null;
          if (responseBytes == 0 ||
              (expectedResponseBytes != null &&
                  responseBytes != expectedResponseBytes)) {
            throw Exception('下载响应不完整');
          }
          if ((total > 0 && downloaded == total) ||
              (total == 0 && streamed.statusCode == 200)) {
            break;
          }
          throw Exception('安装包尚未下载完整');
        } catch (e) {
          if (sink != null) {
            try {
              await sink.flush();
              await sink.close();
            } catch (_) {}
            sink = null;
          }
          if (_disposed || AuthSession.revision != _sessionRevision) rethrow;
          retryCount++;
          if (retryCount > maxRetries) {
            throw Exception('网络连接中断且重试超限: $e');
          }

          // 短暂等待后断点续传（切回前台或后台恢复时无缝接力）
          await Future.delayed(const Duration(milliseconds: 500));
          if (await file.exists()) {
            downloaded = await file.length();
            if (total > 0 && downloaded >= total) {
              // 失败响应即使填满了文件，也不能当成完整包继续安装。
              await file.delete();
              downloaded = 0;
              validator = null;
            }
          }
        } finally {
          streamClient?.close();
          _activeClients.remove(streamClient);
        }
      }

      return file.path;
    } finally {
      // 无论成功失败，下载结束立即清除前台通知并释放唤醒锁
      await lease.release();
    }
  }

  /// 调起系统安装 APK
  Future<void> installApk(String filePath) async {
    try {
      await _downloaderChannel.invokeMethod('installApk', {
        'filePath': filePath,
      });
    } catch (_) {
      // 备用 fallback
      await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
    }
  }

  /// 标记待清理的物理文件路径（下次启动时彻底清除）
  Future<void> markForCleanup(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPendingCleanupPath, filePath);
  }

  /// 启动时清理上次更新的安装包（多重防线，确保 100% 成功清理释放空间）
  static Future<void> cleanupOldApk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingPath = prefs.getString(_keyPendingCleanupPath);

      // 防线 1：根据记录的具体路径直接文件删除
      if (pendingPath != null && pendingPath.isNotEmpty) {
        try {
          final file = File(pendingPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        await prefs.remove(_keyPendingCleanupPath);
      }

      // 防线 2：扫描应用私有目录与下载目录下的全部 *.apk 兜底删除
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final rootApk = File('${extDir.path}/diptych_update.apk');
          if (await rootApk.exists()) {
            try {
              await rootApk.delete();
            } catch (_) {}
          }
          final downloadDir = Directory('${extDir.path}/Download');
          if (await downloadDir.exists()) {
            await for (final entity in downloadDir.list()) {
              if (entity is File && entity.path.endsWith('.apk')) {
                try {
                  await entity.delete();
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// 删除指定安装包
  Future<void> deleteApk(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    for (final client in _activeClients) {
      client.close();
    }
    _activeClients.clear();
  }
}
