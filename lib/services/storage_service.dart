import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../utils/url_helper.dart';
import '../constants/api_config.dart';

/// 支持发送进度字节回调的 MultipartRequest
class _ChunkMultipartRequestWithProgress extends http.MultipartRequest {
  final void Function(int bytesSent)? onBytesSent;

  _ChunkMultipartRequestWithProgress(
    super.method,
    super.url, {
    this.onBytesSent,
  });

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    int bytes = 0;

    return http.ByteStream(
      byteStream.transform(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            bytes += data.length;
            onBytesSent?.call(bytes);
            sink.add(data);
          },
        ),
      ),
    );
  }
}

/// 图片上传服务（分片拆包 + 显式合并引擎）
class StorageService {
  static const String _baseUrl = ApiConfig.apiBaseUrl;

  // 复用 HTTP 连接，避免每次建立新连接
  final http.Client _client = http.Client();

  /// 安全解析流式 JSON
  dynamic _safeDecode(http.StreamedResponse res, {String? body}) {
    try {
      return jsonDecode(body ?? '');
    } catch (e) {
      final preview = (body != null && body.length > 200)
          ? '${body.substring(0, 200)}...'
          : (body ?? '');
      throw Exception('服务器返回非 JSON（状态 ${res.statusCode}）: $preview');
    }
  }

  /// 安全解析普通 Response JSON
  dynamic _safeDecodeBody(String body, int statusCode) {
    try {
      return jsonDecode(body);
    } catch (e) {
      final preview = body.length > 200 ? '${body.substring(0, 200)}...' : body;
      throw Exception('服务器返回非 JSON（状态 $statusCode）: $preview');
    }
  }

  /// 分片上传图片文件，返回下载 URL（单片 1MB，彻底规避网关超时，支持局部重试与合并）
  Future<String> uploadImage(
    File file,
    String folder, {
    void Function(double progress)? onProgress,
  }) async {
    final totalBytes = await file.length();
    if (totalBytes <= 0) {
      throw Exception('文件为空或不存在');
    }

    // 单片 1MB (1024 * 1024 字节)
    const int chunkSize = 1024 * 1024;
    final totalChunks = (totalBytes / chunkSize).ceil();

    final uploadId =
        'upl_${DateTime.now().millisecondsSinceEpoch}_${totalBytes}_${100000 + math.Random().nextInt(900000)}';
    final fileName =
        file.path.split(Platform.pathSeparator).last.split('/').last;

    final raf = await file.open(mode: FileMode.read);

    try {
      onProgress?.call(0.0);

      // ─── 第一阶段：逐片上传 ───
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > totalBytes) ? totalBytes : start + chunkSize;
        final currentChunkSize = end - start;

        await raf.setPosition(start);
        final chunkBytes = await raf.read(currentChunkSize);

        int attempts = 0;
        const maxChunkAttempts = 3;

        while (true) {
          attempts++;
          http.Client? chunkClient;
          try {
            chunkClient = http.Client();

            final uri = Uri.parse('$_baseUrl/upload/chunk');
            final request = _ChunkMultipartRequestWithProgress(
              'POST',
              uri,
              onBytesSent: (bytesSent) {
                // 计算当前整体进度 (0% ~ 95%)
                final bytesInChunk = bytesSent.clamp(0, currentChunkSize);
                final overallBytes = start + bytesInChunk;
                final ratio = (overallBytes / totalBytes).clamp(0.0, 1.0);
                onProgress?.call(ratio * 0.95);
              },
            );

            // 先添加参数字段（确保在 multipart 流中排在文件前面）
            request.fields['upload_id'] = uploadId;
            request.fields['chunk_index'] = i.toString();
            request.fields['total_chunks'] = totalChunks.toString();
            request.fields['folder'] = folder;

            // 添加文件分片
            request.files.add(
              http.MultipartFile.fromBytes(
                'file',
                chunkBytes,
                filename: '${fileName}_$i',
              ),
            );

            // 单个分片 60 秒超时，快速故障重试，绝不触发 Cloudflare 100 秒超时
            final streamed = await chunkClient
                .send(request)
                .timeout(const Duration(seconds: 60));
            final body = await streamed.stream.bytesToString();
            final decoded = _safeDecode(streamed, body: body);

            if (decoded['ok'] != true) {
              throw Exception(decoded['error'] ?? '分片 $i 服务器返回失败');
            }

            // 当前分片成功，跳出重试循环进入下一分片
            break;
          } catch (e) {
            if (attempts >= maxChunkAttempts) {
              throw Exception('分片 $i 上传失败（已重试 $maxChunkAttempts 次）: $e');
            }
            // 局部重试，绝不将整个任务进度归零！等待 500ms 重传当前片
            await Future.delayed(const Duration(milliseconds: 500));
          } finally {
            chunkClient?.close();
          }
        }
      }

      // ─── 第二阶段：通知合并 ───
      onProgress?.call(0.95);

      int mergeAttempts = 0;
      const maxMergeAttempts = 3;

      while (true) {
        mergeAttempts++;
        try {
          final mergeRes = await _client
              .post(
                Uri.parse('$_baseUrl/upload/merge'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'upload_id': uploadId,
                  'filename': fileName,
                  'total_chunks': totalChunks,
                  'folder': folder,
                }),
              )
              .timeout(const Duration(seconds: 60));

          final decoded =
              _safeDecodeBody(mergeRes.body, mergeRes.statusCode);
          if (decoded['ok'] != true) {
            throw Exception(decoded['error'] ?? '文件合并失败');
          }

          final url = decoded['data']?['url'] as String?;
          if (url == null || url.isEmpty) {
            throw Exception('合并成功但未返回图片 URL');
          }

          onProgress?.call(1.0);
          return UrlHelper.normalize(url);
        } catch (e) {
          if (mergeAttempts >= maxMergeAttempts) {
            rethrow;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      await raf.close();
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
