import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日记草稿服务：本地保存/加载/清除
class DraftService {
  static const _prefix = 'draft_';

  /// 保存草稿（文本 + 心情）
  static Future<void> save(String dateStr, String feeling, int? mood) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'feeling': feeling,
      if (mood != null) 'mood': mood,
      'self_image': await _copyToDraft(dateStr, 'self'),
      'partner_image': await _copyToDraft(dateStr, 'partner'),
    };
    await prefs.setString('$_prefix$dateStr', jsonEncode(data));
  }

  /// 加载草稿，无草稿返回 null
  static Future<Map<String, dynamic>?> load(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$dateStr');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // 验证图片文件还存在
      final selfPath = data['self_image'] as String?;
      final partnerPath = data['partner_image'] as String?;
      if (selfPath != null && !File(selfPath).existsSync()) {
        data['self_image'] = null;
      }
      if (partnerPath != null && !File(partnerPath).existsSync()) {
        data['partner_image'] = null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  /// 清除草稿
  static Future<void> clear(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$dateStr');
    // 清理草稿图片
    final dir = await _draftDir();
    final selfFile = File('${dir.path}/${dateStr}_self.jpg');
    final partnerFile = File('${dir.path}/${dateStr}_partner.jpg');
    if (await selfFile.exists()) await selfFile.delete();
    if (await partnerFile.exists()) await partnerFile.delete();
  }

  /// 保存已选图片（原地复制，防止临时文件被清）
  static Future<void> saveImage(String dateStr, String slot, File? file) async {
    if (file == null) return;
    final target = File('${(await _draftDir()).path}/${dateStr}_$slot.jpg');
    await file.copy(target.path);
  }

  static Future<String?> _copyToDraft(String dateStr, String slot) async {
    final target = File('${(await _draftDir()).path}/${dateStr}_$slot.jpg');
    if (await target.exists()) return target.path;
    return null;
  }

  static Future<Directory> _draftDir() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/drafts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
