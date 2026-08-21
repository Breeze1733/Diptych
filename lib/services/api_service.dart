import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../models/moment.dart';
import '../models/app_notification.dart';
import '../constants/api_config.dart';

/// 后端 API 服务 — 替换 Firebase Firestore
class ApiService {
  static const String _baseUrl = ApiConfig.apiBaseUrl;

  // ─── 用户相关 ───

  /// 获取用户信息
  Future<AppUser> getUser(String uid) async {
    final res = await http.get(Uri.parse('$_baseUrl/users/$uid'));
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
  }) async {
    final Map<String, dynamic> data = {};
    if (nickname != null) data['nickname'] = nickname;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (wallpaperDiaryUrl != null) data['wallpaper_diary_url'] = wallpaperDiaryUrl;
    if (wallpaperTopicUrl != null) data['wallpaper_topic_url'] = wallpaperTopicUrl;
    if (wallpaperDiaryOpacity != null) data['wallpaper_diary_opacity'] = wallpaperDiaryOpacity;
    if (wallpaperTopicOpacity != null) data['wallpaper_topic_opacity'] = wallpaperTopicOpacity;
    await http.put(
      Uri.parse('$_baseUrl/users/$uid'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
  }

  /// 确保预设用户存在
  Future<void> ensurePresetUsers() async {
    await http.post(Uri.parse('$_baseUrl/users/ensure'));
  }

  // ─── 动态相关 ───

  /// 获取指定日期指定用户的动态（Future）
  Future<Moment?> getMomentByDate(String userId, String dateStr) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/moments?date_str=$dateStr&author_ids=$userId'),
    );
    if (res.statusCode != 200) return null;
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] == null) return null;
    final list = body['data'] as List;
    if (list.isEmpty) return null;
    return Moment.fromJson(list.first);
  }

  /// 获取指定日期的多人动态
  Future<List<Moment>> getDayMoments(String dateStr, List<String> authorIds) async {
    if (authorIds.isEmpty) return [];
    final ids = authorIds.join(',');
    final res = await http.get(
      Uri.parse('$_baseUrl/moments?date_str=$dateStr&author_ids=$ids'),
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

  /// 安全解析 JSON，解析失败时附带原始响应内容便于排查
  dynamic _safeDecode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (e) {
      final preview = res.body.length > 200 ? '${res.body.substring(0, 200)}...' : res.body;
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

    final res = await http.post(
      Uri.parse('$_baseUrl/moments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final bodyDecoded = _safeDecode(res);
    if (bodyDecoded['ok'] != true) throw Exception(bodyDecoded['error'] ?? '创建失败');
    return bodyDecoded['data']['id'].toString();
  }

  /// 更新动态
  Future<void> updateMoment(String momentId, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/moments/$momentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('PUT /moments/$momentId 返回 ${res.statusCode}: ${res.body}');
    }
  }

  /// 获取用户有动态的日期列表
  Future<List<String>> getDatesWithMoments(String userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/moments/$userId/dates'));
    if (res.statusCode != 200) return [];
    final body = _safeDecode(res);
    if (body['ok'] != true || body['data'] == null) return [];
    return (body['data'] as List).map((e) => e.toString()).toList();
  }

  // ─── 通知相关（单次请求：取出并自毁） ───

  /// 获取待读通知列表（服务端读取后即自毁，超时 4 秒自动跳过防卡顿）
  Future<List<AppNotification>> getPendingNotifications(String userId) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/notifications?user_id=$userId'))
          .timeout(const Duration(seconds: 4));
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
