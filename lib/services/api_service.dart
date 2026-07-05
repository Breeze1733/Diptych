import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../models/moment.dart';

/// 后端 API 服务 — 替换 Firebase Firestore
class ApiService {
  static const String _baseUrl = 'https://example.com/api';

  // ─── 用户相关 ───

  /// 获取用户信息
  Future<AppUser> getUser(String uid) async {
    final res = await http.get(Uri.parse('$_baseUrl/users/$uid'));
    if (res.statusCode != 200) {
      throw Exception('GET /users/$uid 返回 ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) {
      throw Exception('GET /users/$uid 响应异常: ${res.body}');
    }
    return AppUser.fromJson(body['data']);
  }

  /// 更新用户信息（昵称 / 头像）
  Future<void> updateUser(String uid, {String? nickname, String? avatarUrl}) async {
    final Map<String, dynamic> data = {};
    if (nickname != null) data['nickname'] = nickname;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    await http.put(
      Uri.parse('$_baseUrl/users/$uid'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
  }

  /// 创建用户
  Future<void> createUser(AppUser user) async {
    await http.post(
      Uri.parse('$_baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(user.toJson()),
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
    final body = jsonDecode(res.body);
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
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) return [];
    return (body['data'] as List).map((e) => Moment.fromJson(e)).toList();
  }

  /// 创建动态
  Future<String> createMoment({
    required String dateStr,
    required String authorId,
    required String selfImageUrl,
    required String partnerImageUrl,
    required String feeling,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/moments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'date_str': dateStr,
        'author_id': authorId,
        'self_image_url': selfImageUrl,
        'partner_image_url': partnerImageUrl,
        'feeling': feeling,
      }),
    );
    final body = jsonDecode(res.body);
    if (body['ok'] != true) throw Exception(body['error'] ?? '创建失败');
    return body['data']['id'].toString();
  }

  /// 更新动态
  Future<void> updateMoment(String momentId, Map<String, dynamic> data) async {
    await http.put(
      Uri.parse('$_baseUrl/moments/$momentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
  }

  /// 获取用户有动态的日期列表
  Future<List<String>> getDatesWithMoments(String userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/moments/$userId/dates'));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body['ok'] != true || body['data'] == null) return [];
    return (body['data'] as List).map((e) => e.toString()).toList();
  }
}
