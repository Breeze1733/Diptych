import '../utils/url_helper.dart';

/// 用户数据模型
class AppUser {
  final String uid; // "A" 或 "B"
  final String nickname;
  final String partnerUid;
  final String avatarUrl;
  final String wallpaperDiaryUrl;  // 日记壁纸
  final String wallpaperTopicUrl;  // 话题壁纸
  final double wallpaperDiaryOpacity;  // 壁纸不透明度 0~1，默认 1（完全不透明）
  final double wallpaperTopicOpacity;

  const AppUser({
    required this.uid,
    required this.nickname,
    required this.partnerUid,
    this.avatarUrl = '',
    this.wallpaperDiaryUrl = '',
    this.wallpaperTopicUrl = '',
    this.wallpaperDiaryOpacity = 1.0,
    this.wallpaperTopicOpacity = 1.0,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      partnerUid: json['partner_uid'] as String? ?? '',
      avatarUrl: UrlHelper.normalize(json['avatar_url'] as String? ?? ''),
      wallpaperDiaryUrl: UrlHelper.normalize(json['wallpaper_diary_url'] as String? ?? ''),
      wallpaperTopicUrl: UrlHelper.normalize(json['wallpaper_topic_url'] as String? ?? ''),
      wallpaperDiaryOpacity: (json['wallpaper_diary_opacity'] as num?)?.toDouble() ?? 1.0,
      wallpaperTopicOpacity: (json['wallpaper_topic_opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'nickname': nickname,
      'partner_uid': partnerUid,
      'avatar_url': avatarUrl,
      'wallpaper_diary_url': wallpaperDiaryUrl,
      'wallpaper_topic_url': wallpaperTopicUrl,
      'wallpaper_diary_opacity': wallpaperDiaryOpacity,
      'wallpaper_topic_opacity': wallpaperTopicOpacity,
    };
  }

  AppUser copyWith({
    String? nickname,
    String? avatarUrl,
    String? wallpaperDiaryUrl,
    String? wallpaperTopicUrl,
    double? wallpaperDiaryOpacity,
    double? wallpaperTopicOpacity,
  }) {
    return AppUser(
      uid: uid,
      nickname: nickname ?? this.nickname,
      partnerUid: partnerUid,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      wallpaperDiaryUrl: wallpaperDiaryUrl ?? this.wallpaperDiaryUrl,
      wallpaperTopicUrl: wallpaperTopicUrl ?? this.wallpaperTopicUrl,
      wallpaperDiaryOpacity: wallpaperDiaryOpacity ?? this.wallpaperDiaryOpacity,
      wallpaperTopicOpacity: wallpaperTopicOpacity ?? this.wallpaperTopicOpacity,
    );
  }
}
