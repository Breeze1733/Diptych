import 'dart:io';

import '../services/private_image_cache.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/settings_theme.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/cache_service.dart';
import '../services/transfer_keep_alive.dart';
import 'wallpaper_preview_screen.dart';

import 'package:image_cropper/image_cropper.dart';

/// 壁纸设置子页面：分「日记壁纸」「话题壁纸」两个区块
class WallpaperSettingsScreen extends ConsumerStatefulWidget {
  const WallpaperSettingsScreen({super.key});

  @override
  ConsumerState<WallpaperSettingsScreen> createState() =>
      _WallpaperSettingsScreenState();
}

class _WallpaperSettingsScreenState
    extends ConsumerState<WallpaperSettingsScreen> {
  WallpaperType? _uploading; // 正在上传的类型

  /// 选图 + 固定 9:16 比例裁剪，返回裁剪后的图片文件
  Future<File?> _pickAndCrop() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪壁纸',
          toolbarColor: SettingsTheme.ink,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: SettingsTheme.ink,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '裁剪壁纸',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (cropped == null) return null;
    return File(cropped.path);
  }

  /// 上传新壁纸：传云端 → 更新记录 → 清理旧图 → 写本地缓存。
  Future<void> _uploadWallpaper(WallpaperType type) async {
    if (_uploading != null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = await _pickAndCrop();
    if (file == null) return;
    if (!mounted || ref.read(currentUserProvider)?.uid != user.uid) return;

    setState(() => _uploading = type);
    TransferKeepAliveLease? lease;
    try {
      lease = await TransferKeepAlive.acquire();
      if (!mounted) return;
      final storageService = ref.read(storageServiceProvider);
      final apiService = ref.read(apiServiceProvider);
      final settings = ref.read(wallpaperSettingsProvider);

      // 1. 上传新图
      final url = await storageService.uploadImage(file, 'wallpapers');

      // 2. 记录被替换的旧图，远端更新确认后再清理。
      final oldUrl = type == WallpaperType.diary
          ? settings.diaryUrl
          : settings.topicUrl;

      // 3. 推到云端
      if (type == WallpaperType.diary) {
        await apiService.updateUser(user.uid, wallpaperDiaryUrl: url);
      } else {
        await apiService.updateUser(user.uid, wallpaperTopicUrl: url);
      }

      if (oldUrl.isNotEmpty && oldUrl != url) {
        try {
          await storageService.deleteImage(oldUrl);
        } catch (error) {
          debugPrint('壁纸已保存，清理旧图失败: $error');
        }
      }
      // 4. 更新本地（provider + 本地 key + 整对象缓存）
      final newSettings = settings.copyWith(
        diaryUrl: type == WallpaperType.diary ? url : null,
        topicUrl: type == WallpaperType.topic ? url : null,
      );
      try {
        await saveWallpaperSettings(user.uid, newSettings);
        await CacheService.saveUser(_withWallpaper(user, newSettings));
      } catch (error) {
        debugPrint('壁纸已保存，本地缓存更新失败: $error');
      }
      if (!mounted || ref.read(currentUserProvider)?.uid != user.uid) return;
      ref.read(wallpaperSettingsProvider.notifier).setSettings(newSettings);

      // 5. 种子化磁盘缓存：刚上传的壁纸本地立即可用，无需重新下载
      try {
        await PrivateImageCache().cacheOriginal(url, file);
      } catch (_) {}

      // 6. 自动进入透明度预览页
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewScreen(
            type: type,
            url: url,
            initialOpacity: type == WallpaperType.diary
                ? newSettings.diaryOpacity
                : newSettings.topicOpacity,
            initialCardOpacity: newSettings.cardOpacity,
          ),
        ),
      );
    } catch (e) {
      debugPrint('上传壁纸失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('壁纸上传失败，请检查网络后重试'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      await lease?.release();
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// 打开透明度预览页（已有壁纸时调整）
  /// 该类型的透明度预览入口（无壁纸时禁用提示）
  Future<void> _openPreview(WallpaperType type) async {
    final settings = ref.read(wallpaperSettingsProvider);
    final url = type == WallpaperType.diary
        ? settings.diaryUrl
        : settings.topicUrl;
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先设置壁纸，再调整透明度')));
      return;
    }
    final opacity = type == WallpaperType.diary
        ? settings.diaryOpacity
        : settings.topicOpacity;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WallpaperPreviewScreen(
          type: type,
          url: url,
          initialOpacity: opacity,
          initialCardOpacity: settings.cardOpacity,
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
      cardOpacity: s.cardOpacity,
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
    ref.read(wallpaperSettingsProvider.notifier).setSettings(newSettings);
    await saveWallpaperSettings(user.uid, newSettings);
    await CacheService.saveUser(_withWallpaper(user, newSettings));

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已设为白色背景')));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTheme.wrap(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('壁纸')),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 20),
                    child: Text(
                      '给日记和话题，各选一张喜欢的背景。',
                      style: TextStyle(
                        fontSize: 13,
                        color: SettingsTheme.muted,
                        height: 1.6,
                      ),
                    ),
                  ),
                  _buildWallpaperCard(type: WallpaperType.diary),
                  const SizedBox(height: 16),
                  _buildWallpaperCard(type: WallpaperType.topic),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWallpaperCard({required WallpaperType type}) {
    final uploading = _uploading == type;
    final isDiary = type == WallpaperType.diary;
    final settings = ref.watch(wallpaperSettingsProvider);
    final url = isDiary ? settings.diaryUrl : settings.topicUrl;
    final opacity = isDiary ? settings.diaryOpacity : settings.topicOpacity;
    final percent = (opacity * 100).round();
    final cardPercent = (settings.cardOpacity * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SettingsTheme.accentSurface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    isDiary
                        ? Icons.auto_stories_outlined
                        : Icons.forum_outlined,
                    color: SettingsTheme.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDiary ? '日记壁纸' : '话题壁纸',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        url.isEmpty
                            ? '还未设置，选一张喜欢的照片吧'
                            : '壁纸 $percent% · 卡片 $cardPercent%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SettingsTheme.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (uploading) ...[
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '正在上传壁纸，请稍候…',
                      style: TextStyle(
                        fontSize: 12,
                        color: SettingsTheme.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _uploading != null
                      ? null
                      : () => _uploadWallpaper(type),
                  child: const Text('更换壁纸'),
                ),
                OutlinedButton(
                  onPressed: _uploading != null || url.isEmpty
                      ? null
                      : () => _openPreview(type),
                  child: const Text('调透明度'),
                ),
                TextButton(
                  onPressed: _uploading != null || url.isEmpty
                      ? null
                      : () => _setWhite(type),
                  child: const Text('白色背景'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
