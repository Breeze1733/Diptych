import 'dart:convert';

import 'http_request.dart';
import '../models/topic.dart';
import '../constants/api_config.dart';

class TopicService {
  TopicService({HttpRequests? http}) : _http = http ?? HttpRequests();

  static const String _baseUrl = ApiConfig.apiBaseUrl;
  final HttpRequests _http;

  Future<List<Topic>> getTopics() async {
    final res = await _http.get(Uri.parse('$_baseUrl/topics'));
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception(body['error'] ?? '加载失败');
    }
    return (body['data'] as List).map((e) => Topic.fromJson(e)).toList();
  }

  Future<Topic> createTopic(String title, String authorId) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/topics'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'author_id': authorId}),
    );
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception(body['error'] ?? '创建失败');
    }
    return Topic.fromJson(body['data']);
  }

  Future<Topic> getTopic(String id) async {
    final res = await _http.get(Uri.parse('$_baseUrl/topics/$id'));
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception(body['error'] ?? '加载失败');
    }
    return Topic.fromJson(body['data']);
  }

  Future<Post> createPost(
    String topicId,
    String authorId,
    String content,
  ) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/topics/$topicId/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'author_id': authorId, 'content': content}),
    );
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception(body['error'] ?? '发帖失败');
    }
    return Post.fromJson(body['data']);
  }

  Future<void> deletePost(String topicId, String postId) async {
    final res = await _http.delete(
      Uri.parse('$_baseUrl/topics/$topicId/posts/$postId'),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('删除失败（${res.statusCode}）');
    }
    final Object? body = jsonDecode(res.body);
    if (body is! Map<String, dynamic> || body['ok'] != true) {
      throw Exception(body is Map ? body['error'] ?? '删除失败' : '删除失败');
    }
  }
}
