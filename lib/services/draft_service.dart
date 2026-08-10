import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日记草稿服务：本地保存/加载/清除
///
/// 设计要点：
/// - 图片列表由 [save] / [saveImages] 统一复制进草稿目录，按序号命名（第一张为封面）。
/// - prefs 里不存图片路径 —— 绝对路径（尤其 iOS 沙箱）在 App 更新/重装后会失效，
///   加载时扫描当前草稿目录按序号重新解析。
/// - 传入的图片可能就是草稿目录里的文件（草稿加载后再保存），复制时先落到临时文件、
///   删除旧序号文件后再改名，避免序号变动时互相覆盖或 copy 到自身清空文件。
class DraftService {
  static const _prefix = 'draft_';
  static const _commentPrefix = 'comment_draft_';
  static const _topicPostPrefix = 'topic_post_draft_';

  /// 保存评论草稿。key 由日记 ID 和回复目标 ID 组成。
  static Future<void> saveComment(String key, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_commentPrefix$key', content);
  }

  /// 加载评论草稿，无草稿返回 null。
  static Future<String?> loadComment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_commentPrefix$key');
  }

  /// 仅在评论成功发布后清理草稿。
  static Future<void> clearComment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_commentPrefix$key');
  }

  /// 保存话题发帖草稿。
  static Future<void> saveTopicPost(String key, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_topicPostPrefix$key', content);
  }

  /// 加载话题发帖草稿，无草稿返回 null。
  static Future<String?> loadTopicPost(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_topicPostPrefix$key');
  }

  /// 仅在话题发帖成功后清理草稿。
  static Future<void> clearTopicPost(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_topicPostPrefix$key');
  }

  /// 保存草稿（文本 + 心情 + 图片列表，全量替换）
  static Future<void> save(
    String dateStr,
    String feeling,
    int? mood, {
    List<File> images = const [],
  }) async {
    await _persistImages(dateStr, images);

    final prefs = await SharedPreferences.getInstance();
    final data = {
      'feeling': feeling,
      if (mood != null) 'mood': mood, // ignore: use_null_aware_elements
      'image_count': images.length,
    };
    await prefs.setString('$_prefix$dateStr', jsonEncode(data));
  }

  /// 加载草稿，无草稿返回 null。图片扫描草稿目录按序号解析。
  static Future<DraftData?> load(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$dateStr');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return DraftData(
        feeling: data['feeling'] as String? ?? '',
        mood: data['mood'] as int?,
        images: await _resolveImages(dateStr),
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
    await for (final entity in dir.list()) {
      if (entity is File && _fileName(entity).startsWith('${dateStr}_')) {
        try {
          await entity.delete();
        } catch (_) {/* 删失败不阻塞 */}
      }
    }
  }

  /// 选图/删图后可即时调用，把当前图片列表先落地到草稿目录，防止临时文件被系统清理
  static Future<void> saveImages(String dateStr, List<File> images) async {
    await _persistImages(dateStr, images);
  }

  // ─── 私有辅助 ───

  /// 全量替换草稿图片：先复制到临时文件 → 删除旧序号文件 → 改名到位
  static Future<void> _persistImages(String dateStr, List<File> images) async {
    final dir = await _draftDir();

    // 1. 全部复制到临时文件（源文件可能就是旧序号文件，先读后删）
    final tmps = <File>[];
    for (var i = 0; i < images.length; i++) {
      final tmp = File('${dir.path}/${dateStr}_tmp_$i.jpg');
      try {
        await images[i].copy(tmp.path);
        tmps.add(tmp);
      } catch (_) {/* 单张失败跳过 */}
    }

    // 2. 删除旧序号文件
    await for (final entity in dir.list()) {
      if (entity is File && _fileName(entity).startsWith('${dateStr}_img_')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    // 3. 临时文件改名为正式序号文件
    for (var i = 0; i < tmps.length; i++) {
      try {
        await tmps[i].rename('${dir.path}/${dateStr}_img_$i.jpg');
      } catch (_) {}
    }
  }

  /// 扫描草稿目录，按序号顺序返回存在的图片
  static Future<List<File>> _resolveImages(String dateStr) async {
    final dir = await _draftDir();
    final files = <int, File>{};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final match =
            RegExp('^${dateStr}_img_(\\d+)\\.jpg\$').firstMatch(_fileName(entity));
        if (match != null) {
          files[int.parse(match.group(1)!)] = entity;
        }
      }
    }
    final indexes = files.keys.toList()..sort();
    return [for (final i in indexes) files[i]!];
  }

  static String _fileName(File f) => f.path.split(Platform.pathSeparator).last.split('/').last;

  static Future<Directory> _draftDir() async {
    final dir =
        Directory('${(await getApplicationDocumentsDirectory()).path}/drafts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// 草稿数据：图片以运行时解析好的 File 列表提供
class DraftData {
  final String feeling;
  final int? mood;
  final List<File> images;

  const DraftData({
    required this.feeling,
    this.mood,
    this.images = const [],
  });
}
