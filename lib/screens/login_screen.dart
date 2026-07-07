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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final loginAction = ref.read(loginActionProvider);
    final role = await loginAction(_keyController.text.trim());

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (role == null) {
      setState(() => _errorText = AppStrings.loginError);
    }
    // 登录成功后，由 autoLoginProvider 驱动跳转到主页
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo 图标
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 40,
                      height: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 标题
                  const Text(
                    'Diptych',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.loginTitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),

                  // 密钥输入框
                  TextFormField(
                    controller: _keyController,
                    decoration: InputDecoration(
                      labelText: AppStrings.loginHint,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      errorText: _errorText,
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入密钥';
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 24),

                  // 登录按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
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
    );
  }
}
