import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../constants/strings.dart';
import '../providers/auth_provider.dart';

/// 登录页：输入密钥验证身份
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _keyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final loginAction = ref.read(loginActionProvider);
      final role = await loginAction(_keyController.text.trim());
      if (!mounted) return;
      if (role == null) setState(() => _errorText = AppStrings.loginError);
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = '暂时无法登录，请检查网络或稍后重试');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo 图标
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 标题
                    const Text(
                      'Diptych',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.8,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.loginTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '把各自的一天，写在同一页。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 密钥输入框
                    SelectionContainer.disabled(
                      child: TextFormField(
                        enabled: !_isLoading,
                        controller: _keyController,
                        contextMenuBuilder: (context, editableTextState) =>
                            AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems:
                                  editableTextState.contextMenuButtonItems,
                            ),
                        decoration: InputDecoration(
                          labelText: AppStrings.loginHint,
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                          errorText: _errorText,
                        ),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '请输入密钥';
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleLogin(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 登录按钮
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                AppStrings.loginButton,
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
