import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_theme.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../services/update_service.dart';
import '../utils/cache_helper.dart';

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
  String _updateStatus = '';         // 状态文字
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  VersionInfo? _latestVersion;       // 检查到的最新版本；有值时下载按钮可用

  // 缓存相关
  String _cacheSizeText = '点击计算';
  bool _isClearingCache = false;
  bool _isCalcCache = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _updateService.dispose();
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
          toolbarColor: AppTheme.primaryColor,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppTheme.primaryColor,
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
    if (cropped != null) setState(() => _avatarFile = File(cropped.path));
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final apiService = ref.read(apiServiceProvider);
      String? avatarUrl;
      if (_avatarFile != null) {
        final storageService = ref.read(storageServiceProvider);
        avatarUrl = await storageService.uploadImage(_avatarFile!, 'avatars');
        if (user.avatarUrl.isNotEmpty) storageService.deleteImage(user.avatarUrl);
      }

      final newNickname = _nicknameController.text.trim();
      await apiService.updateUser(
        user.uid,
        nickname: newNickname.isNotEmpty ? newNickname : null,
        avatarUrl: avatarUrl,
      );

      ref.read(currentUserProvider.notifier).state = user.copyWith(
        nickname: newNickname.isNotEmpty ? newNickname : user.nickname,
        avatarUrl: avatarUrl ?? user.avatarUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功'), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── 版本更新 ───

  Future<void> _checkUpdate() async {
    setState(() {
      _isChecking = true;
      _updateStatus = '正在检查更新...';
      _latestVersion = null; // 重新检查前清空，下载按钮先置灰
    });

    try {
      final current = await _updateService.getCurrentVersion();
      final latest = await _updateService.checkLatestVersion();

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
      setState(() {
        _isChecking = false;
        _updateStatus = '检查失败: $e';
      });
    }
  }

  /// 下载并安装（仅设置页内可触发）
  Future<void> _downloadAndInstall() async {
    final latest = _latestVersion;
    if (latest == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _updateStatus = '正在下载...';
    });

    String? apkPath;

    try {
      apkPath = await _updateService.downloadApk(latest.downloadUrl, (progress) {
        setState(() {
          _downloadProgress = progress;
          _updateStatus = '正在下载 ${(progress * 100).toStringAsFixed(0)}%';
        });
      });

      setState(() {
        _isDownloading = false;
        _updateStatus = '正在安装...';
      });

      await _updateService.installApk(apkPath);

      // 安装完成后，下次打开 APP 时自动清理安装包
      setState(() => _updateStatus = '请在安装完成后重新打开 APP');
      // 记录待清理的文件路径
      _updateService.markForCleanup(apkPath);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _updateStatus = '更新失败: $e';
      });
      // 清理失败的下载
      if (apkPath != null) _updateService.deleteApk(apkPath);
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
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将清除日记缓存、图片缓存和临时文件，不会影响已发布的日记数据。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('确定'),
          ),
        ],
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
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClearingCache = false;
        _cacheSizeText = '清理失败';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── 退出登录 ───

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
    if (confirmed == true) {
      final logout = ref.read(logoutActionProvider);
      await logout();
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: user == null
          ? const Center(child: Text('用户数据未加载'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ═══ 用户信息 ═══
                _buildSectionHeader('个人信息'),
                const SizedBox(height: 12),
                _buildUserInfoCard(user),
                const SizedBox(height: 32),

                // ═══ 系统 ═══
                _buildSectionHeader('系统'),
                const SizedBox(height: 12),
                _buildUpdateCard(),
                const SizedBox(height: 16),
                _buildCacheCard(),
                const SizedBox(height: 32),
                // 退出登录（小字，不常用）
                Center(
                  child: GestureDetector(
                    onTap: () => _handleLogout(context, ref),
                    child: Text(
                      '退出登录',
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500));
  }

  Widget _buildUserInfoCard(AppUser user) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 头像
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundImage: _avatarFile != null
                        ? FileImage(_avatarFile!)
                        : (user.avatarUrl.isNotEmpty ? CachedNetworkImageProvider(user.avatarUrl) : null),
                    child: (_avatarFile == null && user.avatarUrl.isEmpty)
                        ? Text(user.nickname.isNotEmpty ? user.nickname[0] : '?',
                            style: const TextStyle(fontSize: 32))
                        : null,
                  ),
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.primaryColor,
                      child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 昵称
            SelectionContainer.disabled(
              child: TextField(
                controller: _nicknameController,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: editableTextState.contextMenuButtonItems,
                ),
                decoration: const InputDecoration(
                  labelText: '昵称',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 保存
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: _isSaving ? null : _handleSave,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheCard() {
    final bool hasCalc = !_isCalcCache && _cacheSizeText != '点击计算';
    final bool isLoading = _isCalcCache || _isClearingCache;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services_outlined, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('缓存管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      Text(
                        hasCalc ? '当前占用 $_cacheSizeText' : _cacheSizeText,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else if (hasCalc)
                  OutlinedButton(
                    onPressed: _clearCache,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('清理', style: TextStyle(fontSize: 14)),
                  )
                else
                  FilledButton(
                    onPressed: _calcCacheSize,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('计算', style: TextStyle(fontSize: 14)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateCard() {
    // 下载中：两个按钮都消失，只显示进度条
    if (_isDownloading) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('正在下载更新',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _downloadProgress, color: AppTheme.primaryColor),
              const SizedBox(height: 8),
              Text(
                _updateStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: _updateStatus.contains('失败') ? Colors.red : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // 常态：检查更新 + 下载更新两个按钮
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.system_update, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('检查更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      Text('检测并安装最新版本', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isChecking ? null : _checkUpdate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(_isChecking ? '检查中' : '检查更新',
                      style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '下载更新',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                // 无可用更新时置灰，有更新（_latestVersion 非空）才可点
                FilledButton(
                  onPressed: _latestVersion == null ? null : _downloadAndInstall,
                  style: FilledButton.styleFrom(
                    backgroundColor: _latestVersion == null
                        ? Colors.grey.shade300
                        : AppTheme.primaryColor,
                    foregroundColor: _latestVersion == null ? Colors.grey.shade500 : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('下载更新', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
            if (_updateStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _updateStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: _updateStatus.contains('失败') ? Colors.red : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
