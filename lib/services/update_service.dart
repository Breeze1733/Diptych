import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

/// 更新检测与安装服务
class UpdateService {
  static const String baseUrl = 'https://example.com/api';
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

  /// 下载 APK，返回文件路径
  Future<String> downloadApk(String url, void Function(double)? onProgress) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/diptych_update.apk');

    final request = http.Request('GET', Uri.parse(url));
    final streamed = await _client.send(request);
    final total = streamed.contentLength ?? 0;
    var downloaded = 0;
    final sink = file.openWrite();

    await for (final chunk in streamed.stream) {
      downloaded += chunk.length;
      sink.add(chunk);
      if (total > 0 && onProgress != null) {
        onProgress(downloaded / total);
      }
    }

    await sink.flush();
    await sink.close();
    return file.path;
  }

  /// 安装 APK
  Future<void> installApk(String filePath) async {
    await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
  }

  /// 删除安装包
  Future<void> deleteApk(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    _client.close();
  }
}
