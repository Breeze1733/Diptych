import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/url_helper.dart';
import '../constants/api_config.dart';

/// 图片上传服务
class StorageService {
  static const String _baseUrl = ApiConfig.apiBaseUrl;

  // 复用 HTTP 连接，避免每次建立新连接
  final http.Client _client = http.Client();

  /// 安全解析 JSON
  dynamic _safeDecode(http.StreamedResponse res, {String? body}) {
    try {
      return jsonDecode(body ?? '');
    } catch (e) {
      final preview = (body != null && body.length > 200) ? '${body.substring(0, 200)}...' : (body ?? '');
      throw Exception('服务器返回非 JSON（状态 ${res.statusCode}）: $preview');
    }
  }

  /// 上传图片文件，返回下载 URL（流式上传，支持 3 次网络重连重试）
  Future<String> uploadImage(File file, String folder) async {
    int attempts = 0;
    const maxAttempts = 3;

    while (true) {
      attempts++;
      http.Client? client;
      try {
        client = http.Client();
        final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: file.path.split('/').last,
        ));
        request.fields['folder'] = folder;

        final streamed = await client.send(request);
        final body = await streamed.stream.bytesToString();
        final decoded = _safeDecode(streamed, body: body);
        if (decoded['ok'] != true) {
          throw Exception(decoded['error'] ?? '服务器返回失败');
        }
        final url = decoded['data']['url'] as String;
        if (url.isEmpty) throw Exception('上传成功但未返回图片 URL');
        return UrlHelper.normalize(url);
      } catch (e) {
        if (attempts >= maxAttempts) {
          rethrow;
        }
        // 遇到网络抖动/切后台断开，等待 500ms 自动重试
        await Future.delayed(const Duration(milliseconds: 500));
      } finally {
        client?.close();
      }
    }
  }

  /// 删除服务器上的旧图片
  Future<void> deleteImage(String url) async {
    if (url.isEmpty) return;
    await _client.post(
      Uri.parse('$_baseUrl/upload/delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );
  }
}
