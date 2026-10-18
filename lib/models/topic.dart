import '../utils/date_helper.dart';

class Topic {
  final String id;
  final String title;
  final String authorId;
  final DateTime createdAt;
  final DateTime latestUpdatedAt;
  final List<Post> posts;

  const Topic({
    required this.id,
    required this.title,
    required this.authorId,
    required this.createdAt,
    DateTime? latestUpdatedAt,
    this.posts = const [],
  }) : latestUpdatedAt = latestUpdatedAt ?? createdAt;

  factory Topic.fromJson(Map<String, dynamic> json) {
    final createdAt = DateHelper.tryParseDateTime(
      json['created_at'] as String? ?? '',
    );
    return Topic(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      authorId: json['author_id'] as String? ?? '',
      createdAt: createdAt,
      latestUpdatedAt:
          DateTime.tryParse(json['latest_updated_at'] as String? ?? '') ??
          createdAt,
      posts:
          (json['posts'] as List<dynamic>?)
              ?.map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Post {
  final String id;
  final String topicId;
  final String authorId;
  final String content;
  final DateTime createdAt;

  const Post({
    required this.id,
    required this.topicId,
    required this.authorId,
    required this.content,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id']?.toString() ?? '',
      topicId: json['topic_id'] as String? ?? '',
      authorId: json['author_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: DateHelper.tryParseDateTime(
        json['created_at'] as String? ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic_id': topicId,
      'author_id': authorId,
      'content': content,
      'created_at': DateHelper.toIsoString(createdAt),
    };
  }
}
