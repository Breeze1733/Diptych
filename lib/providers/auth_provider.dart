import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/auth_session.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

/// 认证服务实例
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// API 服务实例
final apiServiceProvider = Provider<ApiService>((ref) {
  ref.watch(currentUserRoleProvider);
  return ApiService();
});

/// Storage 服务实例
final storageServiceProvider = Provider<StorageService>((ref) {
  ref.watch(currentUserRoleProvider);
  return StorageService();
});

/// 当前登录用户角色 ("A" 或 "B")，null 表示未登录
class CurrentUserRoleNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setRole(String? role) => state = role;
}

final currentUserRoleProvider =
    NotifierProvider<CurrentUserRoleNotifier, String?>(
      CurrentUserRoleNotifier.new,
    );

/// 当前用户信息
class CurrentUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void setUser(AppUser? user) => state = user;
}

final currentUserProvider = NotifierProvider<CurrentUserNotifier, AppUser?>(
  CurrentUserNotifier.new,
);

/// 对方信息
class PartnerUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void setUser(AppUser? user) => state = user;
}

final partnerUserProvider = NotifierProvider<PartnerUserNotifier, AppUser?>(
  PartnerUserNotifier.new,
);

/// Installed once by the app. An old expiry/401 event must never log out a new
/// session, even if the user signs back into the same role before delivery.
final authSessionLifecycleProvider = Provider<void>((ref) {
  final authService = ref.read(authServiceProvider);
  final subscription = AuthSession.invalidations.listen((revision) {
    if (!ref.mounted || AuthSession.revision != revision) return;
    final cleanup = authService.logout();
    ref.read(currentUserRoleProvider.notifier).setRole(null);
    ref.read(currentUserProvider.notifier).setUser(null);
    ref.read(partnerUserProvider.notifier).setUser(null);
    unawaited(
      cleanup.catchError((Object error) {
        debugPrint('登录状态已失效，清理本地会话失败: $error');
      }),
    );
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
});

/// 尝试自动登录：从 SharedPreferences 读取已保存的角色
final autoLoginProvider = FutureProvider<String?>((ref) async {
  final authService = ref.read(authServiceProvider);
  final role = await authService.getUserRole();
  if (role != null) {
    ref.read(currentUserRoleProvider.notifier).setRole(role);
  }
  return role;
});

/// 登录操作
final loginActionProvider = Provider<Future<String?> Function(String key)>((
  ref,
) {
  return (String key) async {
    final authService = ref.read(authServiceProvider);
    final role = await authService.login(key);
    if (role != null) {
      ref.read(currentUserRoleProvider.notifier).setRole(role);
    }
    return role;
  };
});

/// 退出登录
final logoutActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final authService = ref.read(authServiceProvider);
    final cleanup = authService.logout();
    ref.read(currentUserRoleProvider.notifier).setRole(null);
    ref.read(currentUserProvider.notifier).setUser(null);
    ref.read(partnerUserProvider.notifier).setUser(null);
    await cleanup;
  };
});

/// 加载当前用户和对方信息（缓存优先秒开，后台静默更新）
final loadUsersProvider = FutureProvider<void>((ref) async {
  final role = ref.watch(currentUserRoleProvider);
  if (role == null) return;
  final sessionToken = AuthSession.token;
  final sessionRevision = AuthSession.revision;
  bool isCurrentSession() =>
      ref.mounted &&
      ref.read(currentUserRoleProvider) == role &&
      AuthSession.revision == sessionRevision &&
      AuthSession.token == sessionToken;

  final apiService = ref.read(apiServiceProvider);
  Future<void> refresh() async {
    await apiService.ensurePresetUsers();
    if (!isCurrentSession()) return;
    final currentUser = await apiService.getUser(role);
    if (!isCurrentSession()) return;
    final partner = await apiService.getUser(currentUser.partnerUid);
    if (!isCurrentSession()) return;

    await CacheService.saveUser(currentUser);
    if (!isCurrentSession()) return;
    await CacheService.saveUser(partner);
    if (!isCurrentSession()) return;
    ref.read(currentUserProvider.notifier).setUser(currentUser);
    ref.read(partnerUserProvider.notifier).setUser(partner);
  }

  // 1. 先尝试从缓存加载（毫秒级，不阻塞 UI）
  final cachedCurrent = await CacheService.loadUser(role);
  if (!isCurrentSession()) return;
  if (cachedCurrent != null) {
    ref.read(currentUserProvider.notifier).setUser(cachedCurrent);
    final cachedPartner = await CacheService.loadUser(cachedCurrent.partnerUid);
    if (!isCurrentSession()) return;
    if (cachedPartner != null) {
      ref.read(partnerUserProvider.notifier).setUser(cachedPartner);
    }
    // 缓存命中 → 立即返回，后台静默更新
    refresh().catchError((_) {});
    return;
  }

  // 2. 无缓存 → 必须等网络（仅首次安装/清缓存后）
  await refresh();
});
