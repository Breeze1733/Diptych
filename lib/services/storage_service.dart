import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/url_helper.dart';

/// 图片上传服务
class StorageService {
  static const String _baseUrl = 'https://example.com/api';

  /// 安全解析 JSON
  dynamic _safeDecode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (e) {
      final preview = res.body.length > 200 ? '${res.body.substring(0, 200)}...' : res.body;
      throw Exception('服务器返回非 JSON（状态 ${res.statusCode}）: $preview');
    }
  }

  /// 上传图片文件，返回下载 URL
  Future<String> uploadImage(File file, String folder) async {
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.path.split('/').last,
    ));
    request.fields['folder'] = folder;

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _safeDecode(res);
    if (body['ok'] != true) {
      throw Exception(body['error'] ?? '服务器返回失败，响应: ${res.body}');
    }
    final url = body['data']['url'] as String;
    if (url.isEmpty) throw Exception('上传成功但未返回图片 URL');
    return UrlHelper.normalize(url);
  }

  /// 删除服务器上的旧图片
  Future<void> deleteImage(String url) async {
    if (url.isEmpty) return;
    await http.post(
      Uri.parse('$_baseUrl/upload/delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );
  }
}
