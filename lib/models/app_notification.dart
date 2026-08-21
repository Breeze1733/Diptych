import '../utils/date_helper.dart';

/// 通知类型
enum AppNotificationType {
  moment, // 对方发布或更新了日记
  momentComment, // 对方在日记中发表了评论/回复
  topicPost, // 对方在话题中发布了帖子
  topicCreated, // 对方创建了新话题
}

/// 通知数据模型
class AppNotification {
  final String id;
  final String recipientId;
  final AppNotificationType type;
  final String title;
  final String content;
  final String? dateStr; // 日记日期（YYYY-MM-DD，用于跳转）
  final String? topicId; // 话题 ID（用于跳转）
  final String? topicTitle; // 话题标题
  final DateTime createdAt;
  final bool isRead; // 本地已读状态

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.content,
    this.dateStr,
    this.topicId,
    this.topicTitle,
    required this.createdAt,
    this.isRead = false,
  });

  /// 从服务端 JSON 创建（默认未读）
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    AppNotificationType parseType(String? raw) {
      switch (raw) {
        case 'momentComment':
          return AppNotificationType.momentComment;
        case 'topicPost':
          return AppNotificationType.topicPost;
        case 'topicCreated':
          return AppNotificationType.topicCreated;
        case 'moment':
        default:
          return AppNotificationType.moment;
      }
    }

    return AppNotification(
      id: json['id']?.toString() ?? '',
      recipientId: json['recipient_id'] as String? ?? '',
      type: parseType(json['type'] as String?),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      dateStr: json['date_str'] as String?,
      topicId: json['topic_id'] as String?,
      topicTitle: json['topic_title'] as String?,
      createdAt: DateHelper.tryParseDateTime(json['created_at'] as String? ?? ''),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  /// 转为本地缓存 JSON
  Map<String, dynamic> toJson() {
    String typeToString(AppNotificationType t) {
      switch (t) {
        case AppNotificationType.momentComment:
          return 'momentComment';
        case AppNotificationType.topicPost:
          return 'topicPost';
        case AppNotificationType.topicCreated:
          return 'topicCreated';
        case AppNotificationType.moment:
          return 'moment';
      }
    }

    return {
      'id': id,
      'recipient_id': recipientId,
      'type': typeToString(type),
      'title': title,
      'content': content,
      if (dateStr != null) 'date_str': dateStr,
      if (topicId != null) 'topic_id': topicId,
      if (topicTitle != null) 'topic_title': topicTitle,
      'created_at': DateHelper.toIsoString(createdAt),
      'is_read': isRead,
    };
  }

  AppNotification copyWith({
    String? id,
    String? recipientId,
    AppNotificationType? type,
    String? title,
    String? content,
    String? dateStr,
    String? topicId,
    String? topicTitle,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      recipientId: recipientId ?? this.recipientId,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      dateStr: dateStr ?? this.dateStr,
      topicId: topicId ?? this.topicId,
      topicTitle: topicTitle ?? this.topicTitle,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
