import '../utils/date_helper.dart';
import '../utils/url_helper.dart';

/// 评论数据模型
class Comment {
  final String id;
  final String authorId; // "A" 或 "B"
  final String content;
  final String? replyTo; // 回复的目标评论 id，null 表示顶级评论
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.authorId,
    required this.content,
    this.replyTo,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id']?.toString() ?? '',
      authorId: json['author_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      replyTo: json['reply_to'] as String?,
      createdAt: DateHelper.tryParseDateTime(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_id': authorId,
      'content': content,
      if (replyTo != null) 'reply_to': replyTo,
      'created_at': DateHelper.toIsoString(createdAt),
    };
  }

  Comment copyWith({String? id, String? authorId, String? content, String? replyTo, DateTime? createdAt}) {
    return Comment(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      content: content ?? this.content,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 动态数据模型（每天每条用户一条）
class Moment {
  final String id;
  final String dateStr; // YYYY-MM-DD
  final String authorId; // "A" 或 "B"
  final String selfImageUrl;
  final String partnerImageUrl;
  final String feeling;
  final int? mood; // 心情分数 1-10，可为空
  final List<Comment> comments; // 评论列表
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
              ?.map((e) => e is Map<String, dynamic> ? Comment.fromJson(e) : Comment(id: '', authorId: '', content: e.toString(), createdAt: DateTime.now()))
              .toList() ??
          [],
      createdAt: DateHelper.tryParseDateTime(json['created_at'] as String? ?? ''),
      updatedAt: DateHelper.tryParseDateTime(json['updated_at'] as String? ?? ''),
    );
  }

  /// 转为 JSON（创建请求体 / 缓存）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date_str': dateStr,
      'author_id': authorId,
      'self_image_url': selfImageUrl,
      'partner_image_url': partnerImageUrl,
      'feeling': feeling,
      if (mood != null) 'mood': mood,
      'comments': comments.map((c) => c.toJson()).toList(),
      'created_at': DateHelper.toIsoString(createdAt),
      'updated_at': DateHelper.toIsoString(updatedAt),
    };
  }

  /// 更新用的 JSON（仅可变字段）
  Map<String, dynamic> toUpdateJson() {
    return {
      'self_image_url': selfImageUrl,
      'partner_image_url': partnerImageUrl,
      'feeling': feeling,
      if (mood != null) 'mood': mood,
      'comments': comments.map((c) => c.toJson()).toList(),
      'updated_at': DateHelper.toIsoString(updatedAt),
    };
  }

  Moment copyWith({
    String? id,
    String? dateStr,
    String? authorId,
    String? selfImageUrl,
    String? partnerImageUrl,
    String? feeling,
    int? mood,
    List<Comment>? comments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Moment(
      id: id ?? this.id,
      dateStr: dateStr ?? this.dateStr,
      authorId: authorId ?? this.authorId,
      selfImageUrl: selfImageUrl ?? this.selfImageUrl,
      partnerImageUrl: partnerImageUrl ?? this.partnerImageUrl,
      feeling: feeling ?? this.feeling,
      mood: mood ?? this.mood,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
