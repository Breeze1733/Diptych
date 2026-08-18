import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import 'auth_provider.dart';

/// 壁纸类型：日记 / 话题，各自独立
enum WallpaperType { diary, topic }

/// 壁纸设置（日记 / 话题两套，互相独立）
class WallpaperSettings {
  final String diaryUrl;
  final String topicUrl;
  final double diaryOpacity; // 0~1，越大壁纸越清晰
  final double topicOpacity;

  const WallpaperSettings({
    this.diaryUrl = '',
    this.topicUrl = '',
    this.diaryOpacity = 1.0,
    this.topicOpacity = 1.0,
  });

  WallpaperSettings copyWith({
    String? diaryUrl,
    String? topicUrl,
    double? diaryOpacity,
    double? topicOpacity,
  }) {
    return WallpaperSettings(
      diaryUrl: diaryUrl ?? this.diaryUrl,
      topicUrl: topicUrl ?? this.topicUrl,
      diaryOpacity: diaryOpacity ?? this.diaryOpacity,
      topicOpacity: topicOpacity ?? this.topicOpacity,
    );
  }
}

/// 本地壁纸设置 key（独立于 AppUser 缓存，作为"本地优先"主源）
const _keyDiaryUrl = 'wallpaper_diary_url';
const _keyTopicUrl = 'wallpaper_topic_url';
const _keyDiaryOpacity = 'wallpaper_diary_opacity';
const _keyTopicOpacity = 'wallpaper_topic_opacity';

/// 壁纸状态 Provider：启动时由 [initWallpaperProvider] 填充
class WallpaperSettingsNotifier extends Notifier<WallpaperSettings> {
  @override
  WallpaperSettings build() => const WallpaperSettings();

  void setSettings(WallpaperSettings settings) => state = settings;
}

final wallpaperSettingsProvider =
    NotifierProvider<WallpaperSettingsNotifier, WallpaperSettings>(
        WallpaperSettingsNotifier.new);

/// 启动初始化壁纸（依赖当前用户：登录后本地优先，云端兜底）。
/// currentUser 从 null → 有值时自动重跑一次，保证登录后能取到云端壁纸。
final initWallpaperProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentUserProvider);
  final settings = await buildWallpaperSettings(user);
  ref.read(wallpaperSettingsProvider.notifier).setSettings(settings);
  await saveWallpaperSettings(settings);
});

/// 从本地 SharedPreferences 读取壁纸设置
Future<WallpaperSettings> loadWallpaperSettings() async {
  final prefs = await SharedPreferences.getInstance();
  return WallpaperSettings(
    diaryUrl: prefs.getString(_keyDiaryUrl) ?? '',
    topicUrl: prefs.getString(_keyTopicUrl) ?? '',
    diaryOpacity: prefs.getDouble(_keyDiaryOpacity) ?? 1.0,
    topicOpacity: prefs.getDouble(_keyTopicOpacity) ?? 1.0,
  );
}

/// 保存壁纸设置到本地（本地优先主源）
Future<void> saveWallpaperSettings(WallpaperSettings settings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyDiaryUrl, settings.diaryUrl);
  await prefs.setString(_keyTopicUrl, settings.topicUrl);
  await prefs.setDouble(_keyDiaryOpacity, settings.diaryOpacity);
  await prefs.setDouble(_keyTopicOpacity, settings.topicOpacity);
}

/// 计算壁纸设置：
/// - 本地有壁纸 → 直接用本地（不检查云端是否一致，本地优先）
/// - 本地没有 → 用 AppUser（云端/缓存）兜底
/// 透明度同理：本地有 key 用本地，缺省才用 AppUser 的值。
Future<WallpaperSettings> buildWallpaperSettings(AppUser? user) async {
  final prefs = await SharedPreferences.getInstance();
  final localDiaryUrl = prefs.getString(_keyDiaryUrl);
  final localTopicUrl = prefs.getString(_keyTopicUrl);

  final diaryUrl = localDiaryUrl?.isNotEmpty == true
      ? localDiaryUrl!
      : (user?.wallpaperDiaryUrl ?? '');
  final topicUrl = localTopicUrl?.isNotEmpty == true
      ? localTopicUrl!
      : (user?.wallpaperTopicUrl ?? '');

  final localDiaryOpacity = prefs.getDouble(_keyDiaryOpacity);
  final localTopicOpacity = prefs.getDouble(_keyTopicOpacity);

  return WallpaperSettings(
    diaryUrl: diaryUrl,
    topicUrl: topicUrl,
    diaryOpacity: localDiaryOpacity ?? (user?.wallpaperDiaryOpacity ?? 1.0),
    topicOpacity: localTopicOpacity ?? (user?.wallpaperTopicOpacity ?? 1.0),
  );
}
