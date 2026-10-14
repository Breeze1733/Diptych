import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/settings_theme.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/update_service.dart';
import '../services/network_diagnostics_service.dart';
import '../services/cache_service.dart';
import '../utils/cache_helper.dart';
import '../utils/wakelock_helper.dart';
import '../widgets/network_diagnostics_card.dart';
import 'wallpaper_settings_screen.dart';

/// 个人设置页：修改用户信息 + 检查更新
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nicknameController;
  File? _avatarFile;
  bool _isSaving = false;

  // 更新相关
  final _updateService = UpdateService();
  final _networkService = NetworkDiagnosticsService();
  String? _currentVersion;
  String _updateStatus = ''; // 状态文字
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  VersionInfo? _latestVersion; // 检查到的最新版本；有值时下载按钮可用
  String? _downloadedApkPath; // 已下载完成的 APK 路径，支持随时直接点「立即安装」

  // 缓存相关
  String _cacheSizeText = '点击计算';
  bool _isClearingCache = false;
  bool _isCalcCache = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await _updateService.getCurrentVersion();
      if (mounted) setState(() => _currentVersion = info.version);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _updateService.dispose();
    _networkService.dispose();
    super.dispose();
  }

  // ─── 用户信息 ───

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪头像',
          toolbarColor: SettingsTheme.ink,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: SettingsTheme.ink,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
          aspectRatioPresets: const [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );
    if (cropped != null && mounted) {
      setState(() => _avatarFile = File(cropped.path));
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    if (_avatarFile != null) {
      await WakelockHelper.acquire(timeout: const Duration(minutes: 5));
    }
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final apiService = ref.read(apiServiceProvider);
      String? avatarUrl;
      if (_avatarFile != null) {
        final storageService = ref.read(storageServiceProvider);
        avatarUrl = await storageService.uploadImage(_avatarFile!, 'avatars');
        if (user.avatarUrl.isNotEmpty) {
          storageService.deleteImage(user.avatarUrl);
        }
      }

      final newNickname = _nicknameController.text.trim();
      await apiService.updateUser(
        user.uid,
        nickname: newNickname.isNotEmpty ? newNickname : null,
        avatarUrl: avatarUrl,
      );

      final updatedUser = user.copyWith(
        nickname: newNickname.isNotEmpty ? newNickname : user.nickname,
        avatarUrl: avatarUrl ?? user.avatarUrl,
      );
      await CacheService.saveUser(updatedUser);
      if (!mounted) return;
      ref.read(currentUserProvider.notifier).setUser(updatedUser);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存成功'),
          backgroundColor: SettingsTheme.ink,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('保存个人资料失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败，请稍后重试'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (_avatarFile != null) {
        await WakelockHelper.release();
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── 版本更新 ───

  Future<void> _checkUpdate() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _updateStatus = '正在检查更新...';
      _latestVersion = null; // 重新检查前清空，下载按钮先置灰
    });

    try {
      final current = await _updateService.getCurrentVersion();
      final latest = await _updateService.checkLatestVersion();
      if (!mounted) return;

      if (_updateService.needUpdate(current, latest)) {
        setState(() {
          _isChecking = false;
          _latestVersion = latest;
          _updateStatus = '发现新版本 ${latest.version}\n${latest.releaseNotes}';
        });
      } else {
        setState(() {
          _isChecking = false;
          _updateStatus = '已是最新版本 (${current.version})';
        });
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _updateStatus = '检查更新失败，请检查网络后重试';
      });
    }
  }

  /// 全速下载并安装（直连流式满速下载 + 10 分钟 WakeLock 后台防中断）
  Future<void> _downloadAndInstall() async {
    final latest = _latestVersion;
    if (latest == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _updateStatus = '正在全速下载...';
    });

    String? apkPath;

    try {
      apkPath = await _updateService.downloadApk(
        latest.downloadUrl,
        onProgress: (progress, downloaded, total) {
          if (!mounted) return;
          final percent = (progress * 100).toStringAsFixed(0);
          final downloadedMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
          final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _downloadProgress = progress;
            _updateStatus = '正在下载 $percent% ($downloadedMB MB / $totalMB MB)';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadedApkPath = apkPath;
        _updateStatus = '下载完成，已调起安装。若未弹出可直接点击「立即安装」';
      });

      // 标记待清理（下次启动时自动彻底删除安装包）
      await _updateService.markForCleanup(apkPath);

      await _updateService.installApk(apkPath);
    } catch (e) {
      debugPrint('下载更新失败: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _updateStatus = '下载失败，请检查网络或存储权限后重试';
        });
      }
      if (apkPath != null) {
        _updateService.deleteApk(apkPath);
      }
    }
  }

  // ─── 缓存管理 ───

  Future<void> _calcCacheSize() async {
    setState(() {
      _isCalcCache = true;
      _cacheSizeText = '计算中...';
    });

    try {
      final total = await CacheHelper.getTotalCacheSize();
      if (!mounted) return;
      setState(() {
        _isCalcCache = false;
        _cacheSizeText = CacheHelper.formatSize(total);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCalcCache = false;
        _cacheSizeText = '获取失败';
      });
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => SettingsTheme.wrap(
        ctx,
        AlertDialog(
          title: const Text('清理缓存'),
          content: const Text('将清除日记缓存、图片缓存和临时文件，不会影响已发布的日记数据。确定继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: Colors.grey[600])),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: SettingsTheme.ink),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClearingCache = true;
      _cacheSizeText = '清理中...';
    });

    try {
      final freed = await CacheHelper.clearAllCache();
      if (!mounted) return;
      final newSize = await CacheHelper.getTotalCacheSize();
      if (!mounted) return;
      setState(() {
        _isClearingCache = false;
        _cacheSizeText = CacheHelper.formatSize(newSize);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已释放 ${CacheHelper.formatSize(freed)}'),
          backgroundColor: SettingsTheme.ink,
        ),
      );
    } catch (e) {
      debugPrint('清理缓存失败: $e');
      if (!mounted) return;
      setState(() {
        _isClearingCache = false;
        _cacheSizeText = '清理失败';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('清理失败，请稍后重试'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── 退出登录 ───

  Future<void> _handleLogout(WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => SettingsTheme.wrap(
        ctx,
        AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定要退出登录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: Colors.grey[600])),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('退出'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final logout = ref.read(logoutActionProvider);
      await logout();
      if (!mounted) return;
      // 清空导航栈回到根路由：此时根路由已因登出切换为登录页
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return SettingsTheme.wrap(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _buildIntro(),
                  const SizedBox(height: 28),
                  _buildSectionHeader('个人信息'),
                  const SizedBox(height: 12),
                  if (user != null)
                    _buildUserInfoCard(user)
                  else
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          '个人资料暂未加载，可先检测网络连接。',
                          style: TextStyle(color: SettingsTheme.muted),
                        ),
                      ),
                    ),
                  const SizedBox(height: 26),
                  _buildSectionHeader('外观'),
                  const SizedBox(height: 12),
                  _buildWallpaperCard(),
                  const SizedBox(height: 26),
                  _buildSectionHeader('系统'),
                  const SizedBox(height: 12),
                  _buildUpdateCard(),
                  const SizedBox(height: 12),
                  NetworkDiagnosticsCard(service: _networkService),
                  const SizedBox(height: 12),
                  _buildCacheCard(),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _handleLogout(ref),
                      style: TextButton.styleFrom(
                        foregroundColor: SettingsTheme.danger,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 17),
                      label: const Text('退出登录', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Row(
      children: [
        Image.asset('assets/icon.png', width: 46, height: 46),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你的 Diptych',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '各自的视角，共同的日子。',
                style: TextStyle(fontSize: 12, color: SettingsTheme.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          color: SettingsTheme.muted,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _sectionIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: SettingsTheme.accentSurface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: SettingsTheme.accent, size: 22),
    );
  }

  Widget _cardHeader(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        _sectionIcon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
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
    );
  }

  void _openWallpaper() {
    _networkService.cancel();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WallpaperSettingsScreen()),
    );
  }

  Widget _buildWallpaperCard() {
    final wallpaper = ref.watch(wallpaperSettingsProvider);
    final hasAny =
        wallpaper.diaryUrl.isNotEmpty || wallpaper.topicUrl.isNotEmpty;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openWallpaper,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _cardHeader(
                  Icons.wallpaper_rounded,
                  '壁纸',
                  hasAny ? '调整日记与话题的背景' : '为共同的日子添一点色彩',
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: SettingsTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(AppUser user) {
    final hasAvatar = _avatarFile != null || user.avatarUrl.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  label: '更换头像',
                  button: true,
                  child: InkWell(
                    onTap: _isSaving ? null : _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: SettingsTheme.softSurface,
                          foregroundColor: SettingsTheme.ink,
                          backgroundImage: _avatarFile != null
                              ? FileImage(_avatarFile!)
                              : user.avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(user.avatarUrl)
                              : null,
                          child: !hasAvatar
                              ? Text(
                                  user.nickname.isNotEmpty
                                      ? user.nickname.characters.first
                                      : '你',
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              : null,
                        ),
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: SettingsTheme.ink,
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '个人资料',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '点头像更换照片',
                        style: TextStyle(
                          fontSize: 12,
                          color: SettingsTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nicknameController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: '昵称',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('保存资料'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheCard() {
    final isLoading = _isCalcCache || _isClearingCache;
    final hasSize =
        !isLoading && _cacheSizeText != '点击计算' && _cacheSizeText != '获取失败';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              Icons.cleaning_services_outlined,
              '缓存管理',
              hasSize ? '当前占用 $_cacheSizeText' : '管理本机的图片与日记缓存',
            ),
            const SizedBox(height: 16),
            if (isLoading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _cacheSizeText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SettingsTheme.muted,
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _calcCacheSize,
                    child: Text(hasSize ? '重新计算' : '计算占用'),
                  ),
                  if (hasSize)
                    TextButton(
                      onPressed: _clearCache,
                      style: TextButton.styleFrom(
                        foregroundColor: SettingsTheme.danger,
                      ),
                      child: const Text('清理缓存'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              Icons.system_update_alt_rounded,
              '应用更新',
              _currentVersion == null ? '保持最新，记录更顺畅' : '当前版本 $_currentVersion',
            ),
            const SizedBox(height: 16),
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: SettingsTheme.softSurface,
              ),
              const SizedBox(height: 10),
            ] else
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isChecking ? null : _checkUpdate,
                    child: Text(_isChecking ? '检查中…' : '检查更新'),
                  ),
                  if (_downloadedApkPath != null)
                    FilledButton.icon(
                      onPressed: () =>
                          _updateService.installApk(_downloadedApkPath!),
                      icon: const Icon(Icons.install_mobile_rounded, size: 16),
                      label: const Text('立即安装'),
                    )
                  else if (_latestVersion != null)
                    FilledButton(
                      onPressed: _downloadAndInstall,
                      child: const Text('下载更新'),
                    ),
                ],
              ),
            if (_updateStatus.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SettingsTheme.softSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _updateStatus,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: _updateStatus.contains('失败')
                        ? SettingsTheme.danger
                        : SettingsTheme.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
