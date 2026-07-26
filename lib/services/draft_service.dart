import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日记草稿服务：本地保存/加载/清除
///
/// 设计要点：
/// - 图片由 [save] 统一负责复制进草稿目录，不再依赖调用方按顺序先调 [saveImage]。
/// - prefs 里只记录「是否有草稿图」，不存绝对路径 —— 绝对路径（尤其 iOS 沙箱）
///   在 App 更新/重装后会失效，导致草稿图片“丢失”。加载时用当前草稿目录重新解析。
/// - 复制时若源路径与目标路径相同则跳过，避免 File.copy 到自身把文件清空成 0 字节。
class DraftService {
  static const _prefix = 'draft_';

  /// 保存草稿（文本 + 心情 + 图片）
  static Future<void> save(
    String dateStr,
    String feeling,
    int? mood, {
    File? selfImage,
    File? partnerImage,
  }) async {
    // 1. 先把当前选中的图片复制进草稿目录（固定文件名）
    final hasSelf = await _persistImage(dateStr, 'self', selfImage);
    final hasPartner = await _persistImage(dateStr, 'partner', partnerImage);

    // 2. prefs 只记录「是否有图」，图片路径运行时再解析
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'feeling': feeling,
      if (mood != null) 'mood': mood,
      'has_self_image': hasSelf,
      'has_partner_image': hasPartner,
    };
    await prefs.setString('$_prefix$dateStr', jsonEncode(data));
  }

  /// 加载草稿，无草稿返回 null。图片以运行时重新解析的 File 返回。
  static Future<DraftData?> load(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$dateStr');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return DraftData(
        feeling: data['feeling'] as String? ?? '',
        mood: data['mood'] as int?,
        selfImage: await _resolveImage(dateStr, 'self'),
        partnerImage: await _resolveImage(dateStr, 'partner'),
      );
    } catch (_) {
      return null;
    }
  }

  /// 清除草稿（含图片文件）
  static Future<void> clear(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$dateStr');
    final dir = await _draftDir();
    for (final slot in const ['self', 'partner']) {
      final f = _slotFile(dir, dateStr, slot);
      if (await f.exists()) await f.delete();
    }
  }

  /// 选图时可即时调用，把图片先落地到草稿目录，防止临时文件被系统清理
  static Future<void> saveImage(String dateStr, String slot, File? file) async {
    await _persistImage(dateStr, slot, file);
  }

  // ─── 私有辅助 ───

  /// 把图片复制进草稿目录，返回复制后该草稿图是否存在。
  /// - file == null：不改动，返回草稿目录里是否已有该图
  /// - file 就是草稿文件本身：跳过复制（避免 copy 到自身清空文件）
  static Future<bool> _persistImage(String dateStr, String slot, File? file) async {
    final target = _slotFile(await _draftDir(), dateStr, slot);
    if (file == null) {
      return target.exists();
    }
    if (file.path == target.path) {
      return target.exists();
    }
    try {
      await file.copy(target.path);
      return true;
    } catch (_) {
      return target.exists();
    }
  }

  /// 运行时解析草稿图片：用当前草稿目录重新拼路径并校验存在
  static Future<File?> _resolveImage(String dateStr, String slot) async {
    final f = _slotFile(await _draftDir(), dateStr, slot);
    return await f.exists() ? f : null;
  }

  static File _slotFile(Directory dir, String dateStr, String slot) {
    return File('${dir.path}/${dateStr}_$slot.jpg');
  }

  static Future<Directory> _draftDir() async {
    final dir =
        Directory('${(await getApplicationDocumentsDirectory()).path}/drafts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// 草稿数据：图片以运行时解析好的 File 提供（可能为 null）
class DraftData {
  final String feeling;
  final int? mood;
  final File? selfImage;
  final File? partnerImage;

  const DraftData({
    required this.feeling,
    this.mood,
    this.selfImage,
    this.partnerImage,
  });
}
