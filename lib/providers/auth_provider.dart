import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

/// 认证服务实例
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// API 服务实例
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

/// Storage 服务实例
final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

/// 当前登录用户角色 ("A" 或 "B")，null 表示未登录
final currentUserRoleProvider = StateProvider<String?>((ref) => null);

/// 当前用户信息
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

/// 对方信息
final partnerUserProvider = StateProvider<AppUser?>((ref) => null);

/// 尝试自动登录：从 SharedPreferences 读取已保存的角色
final autoLoginProvider = FutureProvider<String?>((ref) async {
  final authService = ref.read(authServiceProvider);
  final role = await authService.getUserRole();
  if (role != null) {
    ref.read(currentUserRoleProvider.notifier).state = role;
  }
  return role;
});

/// 登录操作
final loginActionProvider = Provider<Future<String?> Function(String key)>((ref) {
  return (String key) async {
    final authService = ref.read(authServiceProvider);
    final role = authService.validateKey(key);
    if (role != null) {
      await authService.saveUserRole(role);
      ref.read(currentUserRoleProvider.notifier).state = role;
    }
    return role;
  };
});

/// 退出登录
final logoutActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final authService = ref.read(authServiceProvider);
    await authService.logout();
    ref.read(currentUserRoleProvider.notifier).state = null;
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(partnerUserProvider.notifier).state = null;
  };
});

/// 加载当前用户和对方信息（缓存优先秒开，后台静默更新）
final loadUsersProvider = FutureProvider<void>((ref) async {
  final role = ref.watch(currentUserRoleProvider);
  if (role == null) return;

  // 1. 先尝试从缓存加载（毫秒级，不阻塞 UI）
  final cachedCurrent = await CacheService.loadUser(role);
  if (cachedCurrent != null) {
    ref.read(currentUserProvider.notifier).state = cachedCurrent;
    final cachedPartner = await CacheService.loadUser(cachedCurrent.partnerUid);
    if (cachedPartner != null) {
      ref.read(partnerUserProvider.notifier).state = cachedPartner;
    }
    // 缓存命中 → 立即返回，后台静默更新
    final apiService = ref.read(apiServiceProvider);
    _refreshUsersBg(apiService, role, cachedCurrent.partnerUid);
    return;
  }

  // 2. 无缓存 → 必须等网络（仅首次安装/清缓存后）
  final apiService = ref.read(apiServiceProvider);
  await apiService.ensurePresetUsers();

  final currentUser = await apiService.getUser(role);
  ref.read(currentUserProvider.notifier).state = currentUser;
  await CacheService.saveUser(currentUser);

  final partner = await apiService.getUser(currentUser.partnerUid);
  ref.read(partnerUserProvider.notifier).state = partner;
  await CacheService.saveUser(partner);
});

/// 后台刷新用户信息（不阻塞，失败静默）
void _refreshUsersBg(ApiService api, String role, String partnerUid) {
  Future(() async {
    try {
      await api.ensurePresetUsers();
      final currentUser = await api.getUser(role);
      await CacheService.saveUser(currentUser);
      final partner = await api.getUser(partnerUid);
      await CacheService.saveUser(partner);
    } catch (_) {}
  });
}
