import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/update_service.dart';

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
    if (picked != null) setState(() => _avatarFile = File(picked.path));
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
    });

    try {
      final current = await _updateService.getCurrentVersion();
      final latest = await _updateService.checkLatestVersion();

      if (_updateService.needUpdate(current, latest)) {
        setState(() {
          _isChecking = false;
          _updateStatus = '发现新版本 ${latest.version}\n${latest.releaseNotes}';
        });
        _confirmUpdate(latest);
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

  Future<void> _confirmUpdate(VersionInfo latest) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('当前版本过低，是否更新到 ${latest.version}？\n\n${latest.releaseNotes}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _downloadAndInstall(latest);
    }
  }

  Future<void> _downloadAndInstall(VersionInfo latest) async {
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
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500));
  }

  Widget _buildUserInfoCard(user) {
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
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: '昵称',
                prefixIcon: Icon(Icons.person_outline),
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

  Widget _buildUpdateCard() {
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
                _isChecking || _isDownloading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton(
                        onPressed: _isChecking ? null : _checkUpdate,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text('检测', style: TextStyle(fontSize: 14)),
                      ),
              ],
            ),
            if (_updateStatus.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_isDownloading) ...[
                LinearProgressIndicator(value: _downloadProgress, color: AppTheme.primaryColor),
                const SizedBox(height: 8),
              ],
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
