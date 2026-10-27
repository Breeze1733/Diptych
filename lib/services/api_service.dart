import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/moment.dart';
import '../models/app_notification.dart';
import '../models/shared_moment.dart';
import '../constants/api_config.dart';
import 'http_request.dart';

class SharedMomentConflictException implements Exception {
  final SharedMoment latest;

  const SharedMomentConflictException({required this.latest});

  @override
  String toString() => '共写日记已被对方更新，请基于最新版本继续修改';
}

/// 后端 API 服务 — 替换 Firebase Firestore
class ApiService {
  static const String _baseUrl = ApiConfig.apiBaseUrl;
  final HttpRequests _http;

  ApiService({HttpRequests? http}) : _http = http ?? HttpRequests();

  // ─── 用户相关 ───

  /// 获取用户信息
  Future<AppUser> getUser(String uid) async {
    final res = await _http.get(Uri.parse('$_baseUrl/users/$uid'));
    if (res.statusCode != 200) {
      throw Exception('GET /users/$uid 返回 ${res.statusCode}: ${res.body}');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception('GET /users/$uid 响应异常: ${res.body}');
    }
    return AppUser.fromJson(body['data']);
  }

  /// 更新用户信息（昵称 / 头像 / 壁纸）
  Future<void> updateUser(
    String uid, {
    String? nickname,
    String? avatarUrl,
    String? wallpaperDiaryUrl,
    String? wallpaperTopicUrl,
    double? wallpaperDiaryOpacity,
    double? wallpaperTopicOpacity,
    double? cardOpacity,
  }) async {
    final Map<String, dynamic> data = {};
    if (nickname != null) data['nickname'] = nickname;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (wallpaperDiaryUrl != null) {
      data['wallpaper_diary_url'] = wallpaperDiaryUrl;
    }
    if (wallpaperTopicUrl != null) {
      data['wallpaper_topic_url'] = wallpaperTopicUrl;
    }
    if (wallpaperDiaryOpacity != null) {
      data['wallpaper_diary_opacity'] = wallpaperDiaryOpacity;
    }
    if (wallpaperTopicOpacity != null) {
      data['wallpaper_topic_opacity'] = wallpaperTopicOpacity;
    }
    if (cardOpacity != null) data['card_opacity'] = cardOpacity;
    final res = await _http.put(
      Uri.parse('$_baseUrl/users/$uid'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      throw Exception('PUT /users/$uid 返回 ${res.statusCode}: ${res.body}');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true) {
      throw Exception(body['error'] ?? '更新用户信息失败');
    }
  }

  /// 确保预设用户存在
  Future<void> ensurePresetUsers() async {
    final res = await _http.post(Uri.parse('$_baseUrl/users/ensure'));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('初始化用户失败（${res.statusCode}）');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true) {
      throw Exception(body['error'] ?? '初始化用户失败');
    }
  }

  // ─── 动态相关 ───

  /// 获取指定日期指定用户的动态（Future）
  Future<Moment?> getMomentByDate(String userId, String dateStr) async {
    final moments = await getDayMoments(dateStr, [userId]);
    return moments.isEmpty ? null : moments.first;
  }

  /// 获取指定日期的多人动态
  Future<List<Moment>> getDayMoments(
    String dateStr,
    List<String> authorIds,
  ) async {
    if (authorIds.isEmpty) return [];
    final ids = authorIds.join(',');
    final res = await _http.get(
      Uri.parse('$_baseUrl/moments').replace(
        queryParameters: {
          'date_str': dateStr,
          'author_ids': ids,
          '_fresh': DateTime.now().microsecondsSinceEpoch.toString(),
        },
      ),
      headers: const {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('GET /moments 返回 ${res.statusCode}: ${res.body}');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception('GET /moments 响应异常: ${res.body}');
    }
    return (body['data'] as List).map((e) => Moment.fromJson(e)).toList();
  }

  /// 详情强制读服务端，跳过本地与代理缓存。
  Future<Moment> getMoment(String momentId) async {
    final uri = Uri.parse('$_baseUrl/moments/${Uri.encodeComponent(momentId)}')
        .replace(
          queryParameters: {
            '_fresh': DateTime.now().microsecondsSinceEpoch.toString(),
          },
        );
    final res = await _http.get(
      uri,
      headers: const {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      },
    );
    return _momentResponse(res, momentId);
  }

  /// 单条追加；固定评论 ID 让超时后的重试不会生成重复评论。
  Future<Moment> addComment(String momentId, Comment comment) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/moments/${Uri.encodeComponent(momentId)}/comments'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(comment.toJson()),
    );
    return _momentResponse(res, momentId);
  }

  Future<Moment> deleteComment(
    String momentId,
    String commentId,
    String authorId,
  ) async {
    final res = await _http.delete(
      Uri.parse(
        '$_baseUrl/moments/${Uri.encodeComponent(momentId)}/comments/${Uri.encodeComponent(commentId)}',
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'author_id': authorId}),
    );
    return _momentResponse(res, momentId);
  }

  Moment _momentResponse(http.Response res, String expectedId) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('日记请求失败（${res.statusCode}）');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] is! Map<String, dynamic>) {
      throw Exception(body['error'] ?? '服务器未确认日记数据');
    }
    final moment = Moment.fromJson(body['data']);
    if (moment.id != expectedId) throw Exception('服务器返回了其他日记的数据');
    return moment;
  }

  /// 安全解析 JSON，解析失败时附带原始响应内容便于排查
  dynamic _safeDecode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (e) {
      final preview = res.body.length > 200
          ? '${res.body.substring(0, 200)}...'
          : res.body;
      throw Exception('服务器返回非 JSON（状态 ${res.statusCode}）: $preview');
    }
  }

  /// 创建动态
  Future<String> createMoment({
    required String dateStr,
    required String authorId,
    required List<String> imageUrls,
    required String feeling,
    int? mood,
  }) async {
    final body = <String, dynamic>{
      'date_str': dateStr,
      'author_id': authorId,
      'image_urls': imageUrls,
      'feeling': feeling,
    };
    if (mood != null) body['mood'] = mood;

    final res = await _http.post(
      Uri.parse('$_baseUrl/moments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final bodyDecoded = _safeDecode(res);
    if (bodyDecoded['ok'] != true) {
      throw Exception(bodyDecoded['error'] ?? '创建失败');
    }
    return bodyDecoded['data']['id'].toString();
  }

  /// 更新动态
  Future<void> updateMoment(String momentId, Map<String, dynamic> data) async {
    final res = await _http.put(
      Uri.parse('$_baseUrl/moments/$momentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'PUT /moments/$momentId 返回 ${res.statusCode}: ${res.body}',
      );
    }
    final body = _safeDecode(res);
    if (body['ok'] != true) {
      throw Exception(body['error'] ?? '服务器未确认日记更新');
    }
  }

  // ─── 共写日记 ───

  /// 获取某日共写日记。服务器用 data: null 表示该日期尚未切换模式。
  Future<SharedMoment?> getSharedMoment(String dateStr) async {
    final res = await _http.get(
      Uri.parse('$_baseUrl/shared-moments')
          .replace(queryParameters: {'date_str': dateStr}),
      headers: const {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      },
    );
    final body = _sharedMomentBody(res, 'GET /shared-moments');
    final data = body['data'];
    if (data == null) return null;
    if (data is! Map) {
      throw Exception('GET /shared-moments 响应缺少共写日记数据');
    }
    return SharedMoment.fromJson(Map<String, dynamic>.from(data));
  }

  /// 将某日切换为共记模式；可原子带入当前内容与当天旧双联。
  /// 后端保证重复请求返回同一份记录。
  Future<SharedMoment> activateSharedMoment(
    String dateStr, {
    List<SharedMomentBlock> blocks = const [],
    bool importStandard = false,
  }) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/shared-moments'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'date_str': dateStr,
        if (blocks.isNotEmpty)
          'blocks': blocks.map((block) => block.toJson()).toList(),
        'import_standard': importStandard,
      }),
    );
    return _requiredSharedMoment(res, 'POST /shared-moments');
  }

  Future<SharedMoment> getSharedMomentById(String id) async {
    final encodedId = Uri.encodeComponent(id);
    final res = await _http.get(
      Uri.parse('$_baseUrl/shared-moments/$encodedId'),
      headers: const {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      },
    );
    final result = _requiredSharedMoment(res, 'GET /shared-moments/$encodedId');
    if (result.id != id) throw Exception('服务器返回了其他共写日记的数据');
    return result;
  }

  /// 以 revision 乐观锁保存；冲突时抛出携带服务端最新版的专用异常。
  Future<SharedMoment> updateSharedMoment({
    required SharedMoment moment,
    required List<SharedMomentBlock> blocks,
    List<Map<String, dynamic>> splitForeignText = const [],
  }) async {
    final body = <String, dynamic>{
      'base_revision': moment.revision,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      if (splitForeignText.isNotEmpty) 'split_foreign_text': splitForeignText,
    };
    final encodedId = Uri.encodeComponent(moment.id);
    final res = await _http.put(
      Uri.parse('$_baseUrl/shared-moments/$encodedId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode == 409) {
      final decoded = _safeDecode(res);
      if (decoded is Map && decoded['code'] == 'revision_conflict') {
        final rawData = decoded['data'];
        final rawLatest = rawData is Map && rawData['latest'] is Map
            ? rawData['latest']
            : rawData;
        if (rawLatest is Map) {
          throw SharedMomentConflictException(
            latest: SharedMoment.fromJson(Map<String, dynamic>.from(rawLatest)),
          );
        }
      }
      if (decoded is Map && decoded['error'] is String) {
        throw Exception(decoded['error'] as String);
      }
      throw Exception('共写日记保存冲突，请刷新后重试');
    }

    return _requiredSharedMoment(res, 'PUT /shared-moments/$encodedId');
  }

  Future<List<String>> getSharedMomentDates() async {
    final res = await _http.get(
      Uri.parse('$_baseUrl/shared-moments/dates'),
      headers: const {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      },
    );
    final body = _sharedMomentBody(res, 'GET /shared-moments/dates');
    final data = body['data'];
    final rawDates = data is Map ? data['dates'] : data;
    if (rawDates is! List) {
      throw Exception('GET /shared-moments/dates 响应缺少日期列表');
    }
    return rawDates.map((value) => value.toString()).toList();
  }

  Map _sharedMomentBody(http.Response res, String operation) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('$operation 返回 ${res.statusCode}: ${res.body}');
    }
    final body = _safeDecode(res);
    if (body is! Map || body['ok'] != true) {
      final error = body is Map ? body['error'] : null;
      throw Exception(error ?? '$operation 响应异常');
    }
    return body;
  }

  SharedMoment _requiredSharedMoment(http.Response res, String operation) {
    final body = _sharedMomentBody(res, operation);
    final data = body['data'];
    if (data is! Map) throw Exception('$operation 响应缺少共写日记数据');
    return SharedMoment.fromJson(Map<String, dynamic>.from(data));
  }

  /// 搜索日记内容（从新到旧倒序扫描，支持断点游标续搜）
  Future<({List<Moment> items, bool hasMore, String? nextCursor})>
  searchMoments(
    String keyword,
    List<String> authorIds, {
    int limit = 10,
    String? cursor,
  }) async {
    final params = <String, String>{
      'keyword': keyword,
      if (authorIds.isNotEmpty) 'author_ids': authorIds.join(','),
      'limit': limit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.parse('$_baseUrl/moments/search')
        .replace(queryParameters: params);
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('GET /moments/search 返回 ${res.statusCode}: ${res.body}');
    }
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] is! Map) {
      throw Exception('GET /moments/search 响应异常: ${res.body}');
    }
    final data = body['data'] as Map<String, dynamic>;
    final rawList = data['items'] as List? ?? [];
    final items = rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => Moment.fromJson(e))
        .toList();
    final hasMore = data['has_more'] as bool? ?? false;
    final nextCursor = data['next_cursor']?.toString();
    return (items: items, hasMore: hasMore, nextCursor: nextCursor);
  }

  /// 搜索共写日记文字块。与旧日记搜索保持独立游标和返回模型。
  Future<({List<SharedMoment> items, bool hasMore, String? nextCursor})>
  searchSharedMoments(String keyword, {int limit = 10, String? cursor}) async {
    final params = <String, String>{
      'keyword': keyword,
      'limit': limit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.parse('$_baseUrl/shared-moments/search')
        .replace(queryParameters: params);
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(
        'GET /shared-moments/search 返回 ${res.statusCode}: ${res.body}',
      );
    }
    final body = _safeDecode(res);
    if (body is! Map || body['ok'] != true || body['data'] is! Map) {
      throw Exception('GET /shared-moments/search 响应异常: ${res.body}');
    }
    final data = Map<String, dynamic>.from(body['data'] as Map);
    final rawList = data['items'];
    if (rawList is! List) {
      throw Exception('GET /shared-moments/search 响应缺少结果列表');
    }
    final items = rawList
        .whereType<Map>()
        .map((item) => SharedMoment.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final hasMore = data['has_more'] as bool? ?? false;
    final nextCursor = data['next_cursor']?.toString();
    return (items: items, hasMore: hasMore, nextCursor: nextCursor);
  }

  /// 获取所有用户的日历日期分布 (如 {'A': [...], 'B': [...]})
  Future<Map<String, List<String>>> getCalendarDates() async {
    final res = await _http.get(Uri.parse('$_baseUrl/moments/calendar/dates'));
    if (res.statusCode != 200) {
      throw Exception(
        'GET /moments/calendar/dates 返回 ${res.statusCode}: ${res.body}',
      );
    }
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] is! Map) {
      throw Exception('GET /moments/calendar/dates 响应异常: ${res.body}');
    }
    final Map data = body['data'] as Map;
    return data.map((key, value) {
      final list = (value as List).map((e) => e.toString()).toList();
      return MapEntry(key.toString(), list);
    });
  }

  // ─── 通知相关（单次请求：取出并自毁） ───

  /// 获取待读通知列表（服务端读取后即自毁，超时 4 秒自动跳过防卡顿）
  Future<List<AppNotification>> getPendingNotifications(String userId) async {
    try {
      final res = await _http.get(
        Uri.parse('$_baseUrl/notifications?user_id=$userId'),
        timeout: const Duration(seconds: 4),
      );
      if (res.statusCode != 200) return [];
      final body = _safeDecode(res);
      if (body['ok'] != true || body['data'] == null) return [];
      return (body['data'] as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 离线/网络超时/解析异常静默返回空，不阻塞 UI、不报错
      return [];
    }
  }
}
