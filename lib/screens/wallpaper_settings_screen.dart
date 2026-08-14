import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_theme.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/cache_service.dart';
import 'wallpaper_preview_screen.dart';
import 'wallpaper_zoom_screen.dart';

/// 壁纸设置子页面：分「日记壁纸」「话题壁纸」两个区块
class WallpaperSettingsScreen extends ConsumerStatefulWidget {
  const WallpaperSettingsScreen({super.key});

  @override
  ConsumerState<WallpaperSettingsScreen> createState() =>
      _WallpaperSettingsScreenState();
}

class _WallpaperSettingsScreenState extends ConsumerState<WallpaperSettingsScreen> {
  WallpaperType? _uploading; // 正在上传的类型

  /// 选图 + 放缩调整（无旋转无裁剪），返回调整后的图片文件
  Future<File?> _pickAndAdjust() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;

    final file = File(picked.path);
    if (!mounted) return null;
    final adjusted = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => WallpaperZoomScreen(file: file)),
    );
    return adjusted ?? file; // 未点完成直接返回也保留原图
  }

  /// 上传新壁纸：传云端 → 删旧图 → 写本地缓存 → 自动进预览页
  Future<void> _uploadWallpaper(WallpaperType type) async {
    if (_uploading != null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = await _pickAndAdjust();
    if (file == null) return;

    setState(() => _uploading = type);
    try {
      final storageService = ref.read(storageServiceProvider);
      final apiService = ref.read(apiServiceProvider);
      final settings = ref.read(wallpaperSettingsProvider);

      // 1. 上传新图
      final url = await storageService.uploadImage(file, 'wallpapers');

      // 2. 旧的覆盖掉：删服务器上的旧壁纸图
      final oldUrl = type == WallpaperType.diary ? settings.diaryUrl : settings.topicUrl;
      if (oldUrl.isNotEmpty) storageService.deleteImage(oldUrl);

      // 3. 推到云端
      if (type == WallpaperType.diary) {
        await apiService.updateUser(user.uid, wallpaperDiaryUrl: url);
      } else {
        await apiService.updateUser(user.uid, wallpaperTopicUrl: url);
      }

      // 4. 更新本地（provider + 本地 key + 整对象缓存）
      final newSettings = settings.copyWith(
        diaryUrl: type == WallpaperType.diary ? url : null,
        topicUrl: type == WallpaperType.topic ? url : null,
      );
      ref.read(wallpaperSettingsProvider.notifier).state = newSettings;
      await saveWallpaperSettings(newSettings);
      await CacheService.saveUser(_withWallpaper(user, newSettings));

      // 5. 种子化磁盘缓存：刚上传的壁纸本地立即可用，无需重新下载
      try {
        await DefaultCacheManager().putFile(url, await file.readAsBytes());
      } catch (_) {}

      // 6. 自动进入透明度预览页
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewScreen(
            type: type,
            url: url,
            initialOpacity:
                type == WallpaperType.diary ? newSettings.diaryOpacity : newSettings.topicOpacity,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// 打开透明度预览页（已有壁纸时调整）
  /// 该类型的透明度预览入口（无壁纸时禁用提示）
  Future<void> _openPreview(WallpaperType type) async {
    final settings = ref.read(wallpaperSettingsProvider);
    final url = type == WallpaperType.diary ? settings.diaryUrl : settings.topicUrl;
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置壁纸，再调整透明度')),
      );
      return;
    }
    final opacity =
        type == WallpaperType.diary ? settings.diaryOpacity : settings.topicOpacity;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WallpaperPreviewScreen(
          type: type,
          url: url,
          initialOpacity: opacity,
        ),
      ),
    );
  }

  /// 把壁纸设置合并进 AppUser（用于本地整对象缓存）
  AppUser _withWallpaper(AppUser user, WallpaperSettings s) {
    return user.copyWith(
      wallpaperDiaryUrl: s.diaryUrl,
      wallpaperTopicUrl: s.topicUrl,
      wallpaperDiaryOpacity: s.diaryOpacity,
      wallpaperTopicOpacity: s.topicOpacity,
    );
  }

  /// 「设为白色」：把不透明度拉成 0（壁纸完全透明 → 纯白背景）
  /// 立即写本地，云端不存（壁纸 URL 保留，随时可调回）
  Future<void> _setWhite(WallpaperType type) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final settings = ref.read(wallpaperSettingsProvider);
    final newSettings = settings.copyWith(
      diaryOpacity: type == WallpaperType.diary ? 0.0 : null,
      topicOpacity: type == WallpaperType.topic ? 0.0 : null,
    );
    ref.read(wallpaperSettingsProvider.notifier).state = newSettings;
    await saveWallpaperSettings(newSettings);
    await CacheService.saveUser(_withWallpaper(user, newSettings));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设为白色背景')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('壁纸')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWallpaperCard(type: WallpaperType.diary),
          const SizedBox(height: 24),
          _buildWallpaperCard(type: WallpaperType.topic),
        ],
      ),
    );
  }

  Widget _buildWallpaperCard({required WallpaperType type}) {
    final uploading = _uploading == type;
    final isDiary = type == WallpaperType.diary;
    // 三个按钮统一用「更换壁纸」的绿色实心样式
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: AppTheme.primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    final buttonTextStyle = const TextStyle(fontSize: 13, color: Colors.white);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题放进卡片内部
            Text(
              isDiary ? '日记壁纸' : '话题壁纸',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: uploading
                      ? Row(
                          children: [
                            const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('上传中...',
                                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                // 设为白色：不透明度拉成 0
                FilledButton(
                  onPressed:
                      _uploading != null ? null : () => _setWhite(type),
                  style: buttonStyle,
                  child: Text('设为白色', style: buttonTextStyle),
                ),
                const SizedBox(width: 8),
                // 调透明度
                FilledButton(
                  onPressed: _uploading != null ? null : () => _openPreview(type),
                  style: buttonStyle,
                  child: Text('调透明度', style: buttonTextStyle),
                ),
                const SizedBox(width: 8),
                // 更换壁纸
                FilledButton(
                  onPressed:
                      _uploading != null ? null : () => _uploadWallpaper(type),
                  style: buttonStyle,
                  child: Text('更换壁纸', style: buttonTextStyle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
