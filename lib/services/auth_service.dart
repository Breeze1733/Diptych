import 'package:shared_preferences/shared_preferences.dart';
import '../constants/secrets.dart';

/// 认证服务：密钥验证 + SharedPreferences 持久化
class AuthService {
  static const String _keyUserRole = 'user_role';

  /// 验证密钥，成功返回用户角色 (A/B)，失败返回 null
  String? validateKey(String key) {
    return Secrets.validateKey(key);
  }

  /// 保存用户角色到本地
  Future<void> saveUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserRole, role);
  }

  /// 读取已保存的用户角色（用于自动登录）
  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserRole);
  }

  /// 清除登录状态（退出登录）
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserRole);
  }
}
