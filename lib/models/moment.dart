import '../utils/date_helper.dart';
import '../utils/url_helper.dart';

/// 动态数据模型（每天每条用户一条）
class Moment {
  final String id;
  final String dateStr; // YYYY-MM-DD
  final String authorId; // "A" 或 "B"
  final String selfImageUrl;
  final String partnerImageUrl;
  final String feeling;
  final int? mood; // 心情分数 1-10，可为空
  final List<String> comments; // 对方的评论留言
  final DateTime createdAt;
  final DateTime updatedAt;

  const Moment({
    required this.id,
    required this.dateStr,
    required this.authorId,
    required this.selfImageUrl,
    required this.partnerImageUrl,
    required this.feeling,
    this.mood,
    this.comments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 创建（后端 API 返回格式）
  factory Moment.fromJson(Map<String, dynamic> json) {
    return Moment(
      id: json['id']?.toString() ?? '',
      dateStr: json['date_str'] as String? ?? '',
      authorId: json['author_id'] as String? ?? '',
      selfImageUrl: UrlHelper.normalize(json['self_image_url'] as String? ?? ''),
      partnerImageUrl: UrlHelper.normalize(json['partner_image_url'] as String? ?? ''),
      feeling: json['feeling'] as String? ?? '',
      mood: json['mood'] as int?,
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: DateHelper.tryParseDateTime(json['created_at'] as String? ?? ''),
      updatedAt: DateHelper.tryParseDateTime(json['updated_at'] as String? ?? ''),
    );
  }

  /// 转为 JSON（创建请求体）
  Map<String, dynamic> toJson() {
    return {
      'date_str': dateStr,
      'author_id': authorId,
      'self_image_url': selfImageUrl,
      'partner_image_url': partnerImageUrl,
      'feeling': feeling,
      if (mood != null) 'mood': mood,
    };
  }

  /// 更新用的 JSON（仅可变字段）
  Map<String, dynamic> toUpdateJson() {
    return {
      'self_image_url': selfImageUrl,
      'partner_image_url': partnerImageUrl,
      'feeling': feeling,
      if (mood != null) 'mood': mood,
      'comments': comments,
    };
  }
}
