import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
      ],
      locale: const Locale('zh', 'CN'),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final size = mediaQuery.size;
        final topPadding = mediaQuery.padding.top;
        final bottomPadding = mediaQuery.padding.bottom;

        // 1. 畸形 Padding 拦截（针对小米 HyperOS 等系统将底部手柄错算进 captionBar 导致顶部 padding 膨胀为几百 dp 的已知 Bug）
        final bool isCorruptedTop = topPadding > 60.0 ||
            (size.height > 0 && topPadding > size.height * 0.15);
        final bool isCorruptedBottom = bottomPadding > 80.0 ||
            (size.height > 0 && bottomPadding > size.height * 0.2);

        // 2. 小窗环境检测（悬浮小窗模式下通常宽高显著小于全屏设备）
        // 小窗内部无系统状态栏，顶部 padding 应当紧凑归零，保证顶栏和日期栏不被下推
        final bool isSmallWindow = size.height < 600.0 && size.width < 450.0;

        if (isCorruptedTop || isCorruptedBottom || (isSmallWindow && topPadding > 16.0)) {
          final safeTop = (isCorruptedTop || isSmallWindow) ? 0.0 : topPadding;
          final safeBottom = isCorruptedBottom ? 0.0 : bottomPadding;
          return MediaQuery(
            data: mediaQuery.copyWith(
              padding: mediaQuery.padding.copyWith(top: safeTop, bottom: safeBottom),
              viewPadding: mediaQuery.viewPadding.copyWith(top: safeTop, bottom: safeBottom),
            ),
            child: child ?? const SizedBox(),
          );
        }
        return child ?? const SizedBox();
      },
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

/// 启动闪屏（检查登录状态时显示，无转圈）
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
          ],
        ),
      ),
    );
  }
}