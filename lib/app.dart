import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/feed_screen.dart';
import 'screens/login_screen.dart';

/// 应用根组件：根据认证状态切换页面
class DiptychApp extends ConsumerWidget {
  const DiptychApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听自动登录状态（仅用于判断初始加载完成）
    final autoLoginAsync = ref.watch(autoLoginProvider);
    // 监听当前用户角色（登录/退出后会自动更新）
    final currentRole = ref.watch(currentUserRoleProvider);

    return MaterialApp(
      title: 'Diptych',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: autoLoginAsync.when(
        data: (_) {
          // 根据 currentUserRoleProvider 决定显示哪个页面
          if (currentRole != null) {
            return const FeedScreen();
          }
          return const LoginScreen();
        },
        loading: () => const _SplashScreen(),
        error: (_, _) => const LoginScreen(),
      ),
    );
  }
}

/// 启动闪屏（检查登录状态时显示）
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(image: AssetImage('assets/icon.png'), width: 48, height: 48),
            SizedBox(height: 16),
            Text(
              'Diptych',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: AppTheme.primaryColor),
          ],
        ),
      ),
    );
  }
}
