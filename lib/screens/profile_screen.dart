import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';

/// 个人设置页：改昵称 + 换头像
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nicknameController;
  File? _avatarFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final apiService = ref.read(apiServiceProvider);

      // 上传新头像
      String? avatarUrl;
      if (_avatarFile != null) {
        final storageService = ref.read(storageServiceProvider);
        avatarUrl = await storageService.uploadImage(_avatarFile!, 'avatars');
        // 删旧头像
        if (user.avatarUrl.isNotEmpty) {
          storageService.deleteImage(user.avatarUrl);
        }
      }

      // 更新用户信息
      final newNickname = _nicknameController.text.trim();
      await apiService.updateUser(
        user.uid,
        nickname: newNickname.isNotEmpty ? newNickname : null,
        avatarUrl: avatarUrl,
      );

      // 刷新本地状态
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('个人设置')),
      body: user == null
          ? const Center(child: Text('用户数据未加载'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 头像
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: _avatarFile != null
                              ? FileImage(_avatarFile!)
                              : (user.avatarUrl.isNotEmpty
                                  ? NetworkImage(user.avatarUrl)
                                  : null),
                          child: (_avatarFile == null && user.avatarUrl.isEmpty)
                              ? Text(user.nickname.isNotEmpty ? user.nickname[0] : '?',
                                  style: const TextStyle(fontSize: 36))
                              : null,
                        ),
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primaryColor,
                            child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('点击更换头像', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 32),

                  // 昵称
                  TextField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 保存
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('保存', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
