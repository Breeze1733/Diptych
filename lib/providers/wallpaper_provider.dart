import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'auth_provider.dart';

/// 壁纸类型：日记 / 话题，各自独立
enum WallpaperType { diary, topic }

/// 日记 / 话题壁纸分别设置，卡片不透明度共用。
class WallpaperSettings {
  final String diaryUrl;
  final String topicUrl;
  final double diaryOpacity; // 0~1，越大壁纸越清晰
  final double topicOpacity;
  final double cardOpacity; // 日记与话题共用，只调整背景，保留文字/图片不透明度

  const WallpaperSettings({
    this.diaryUrl = '',
    this.topicUrl = '',
    this.diaryOpacity = 1.0,
    this.topicOpacity = 1.0,
    this.cardOpacity = AppUser.defaultCardOpacity,
  });

  WallpaperSettings copyWith({
    String? diaryUrl,
    String? topicUrl,
    double? diaryOpacity,
    double? topicOpacity,
    double? cardOpacity,
  }) {
    return WallpaperSettings(
      diaryUrl: diaryUrl ?? this.diaryUrl,
      topicUrl: topicUrl ?? this.topicUrl,
      diaryOpacity: diaryOpacity ?? this.diaryOpacity,
      topicOpacity: topicOpacity ?? this.topicOpacity,
      cardOpacity: cardOpacity ?? this.cardOpacity,
    );
  }
}

/// 账号切换时立即清空界面，再由初始化流程加载该账号自己的设置。
class WallpaperSettingsNotifier extends Notifier<WallpaperSettings> {
  @override
  WallpaperSettings build() {
    ref.watch(currentUserProvider.select((user) => user?.uid));
    return const WallpaperSettings();
  }

  void setSettings(WallpaperSettings settings) => state = settings;
}

final wallpaperSettingsProvider =
    NotifierProvider<WallpaperSettingsNotifier, WallpaperSettings>(
      WallpaperSettingsNotifier.new,
    );

final initWallpaperProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentUserProvider);
  final settings = await buildWallpaperSettings(user);
  if (!ref.mounted) return;
  ref.read(wallpaperSettingsProvider.notifier).setSettings(settings);
  if (user != null) await saveWallpaperSettings(user.uid, settings);
});

String _key(String userId, String field) =>
    'wallpaper_${Uri.encodeComponent(userId)}_$field';

/// 旧版全局设置没有账号归属，不自动迁移；缺省从当前账号云端记录恢复。
Future<void> saveWallpaperSettings(
  String userId,
  WallpaperSettings settings,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key(userId, 'diary_url'), settings.diaryUrl);
  await prefs.setString(_key(userId, 'topic_url'), settings.topicUrl);
  await prefs.setDouble(_key(userId, 'diary_opacity'), settings.diaryOpacity);
  await prefs.setDouble(_key(userId, 'topic_opacity'), settings.topicOpacity);
  await prefs.setDouble(_key(userId, 'card_opacity'), settings.cardOpacity);
}

Future<WallpaperSettings> buildWallpaperSettings(AppUser? user) async {
  if (user == null) return const WallpaperSettings();
  final prefs = await SharedPreferences.getInstance();
  return WallpaperSettings(
    diaryUrl:
        prefs.getString(_key(user.uid, 'diary_url')) ?? user.wallpaperDiaryUrl,
    topicUrl:
        prefs.getString(_key(user.uid, 'topic_url')) ?? user.wallpaperTopicUrl,
    diaryOpacity:
        prefs.getDouble(_key(user.uid, 'diary_opacity')) ??
        user.wallpaperDiaryOpacity,
    topicOpacity:
        prefs.getDouble(_key(user.uid, 'topic_opacity')) ??
        user.wallpaperTopicOpacity,
    cardOpacity:
        prefs.getDouble(_key(user.uid, 'card_opacity')) ?? user.cardOpacity,
  );
}
