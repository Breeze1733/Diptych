import '../utils/url_helper.dart';

/// 用户数据模型
class AppUser {
  final String uid; // "A" 或 "B"
  final String nickname;
  final String partnerUid;
  final String avatarUrl;

  const AppUser({
    required this.uid,
    required this.nickname,
    required this.partnerUid,
    this.avatarUrl = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      partnerUid: json['partner_uid'] as String? ?? '',
      avatarUrl: UrlHelper.normalize(json['avatar_url'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'nickname': nickname,
      'partner_uid': partnerUid,
      'avatar_url': avatarUrl,
    };
  }

  AppUser copyWith({String? nickname, String? avatarUrl}) {
    return AppUser(
      uid: uid,
      nickname: nickname ?? this.nickname,
      partnerUid: partnerUid,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  /// 预定义的两位用户
  static const Map<String, AppUser> presetUsers = {
    'A': AppUser(uid: 'A', nickname: '用户A', partnerUid: 'B'),
    'B': AppUser(uid: 'B', nickname: '用户B', partnerUid: 'A'),
  };
}
