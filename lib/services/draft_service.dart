import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'private_image_cache.dart';

import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/motion_photo_helper.dart';
import '../models/moment.dart';

/// 评论和话题草稿。调用方传入的 key 已包含作者与目标标识。
class DraftService {
  static const _commentPrefix = 'comment_draft_';
  static const _pendingCommentPrefix = 'pending_comment_';
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

  static Future<void> savePendingComment(String key, Comment comment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_pendingCommentPrefix$key',
      jsonEncode(comment.toJson()),
    );
  }

  static Future<Comment?> loadPendingComment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pendingCommentPrefix$key');
    if (raw == null) return null;
    try {
      return Comment.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// 仅在评论成功发布后清理草稿。
  static Future<void> clearComment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_commentPrefix$key');
    await prefs.remove('$_pendingCommentPrefix$key');
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
}

/// 一个账号某一天的日记草稿。文件名称与照片顺序无关。
/// 所有写入按调用顺序串行，图片完整落盘后才一次替换清单。
class MomentDraftStore {
  final String userId;
  final String dateStr;
  static final _writes = <String, Future<void>>{};
  static final _sourceNames = <String, Map<String, String>>{};
  static final _random = Random.secure();

  MomentDraftStore({required this.userId, required this.dateStr}) {
    if (userId.isEmpty || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr)) {
      throw ArgumentError('日记草稿需要账号和有效日期');
    }
  }

  String get _scope => '${Uri.encodeComponent(userId)}_$dateStr';
  String get _key => 'moment_draft_v2_$_scope';

  Future<T> _serialized<T>(Future<T> Function() action) =>
      _serialFor(_key, action);

  static Future<T> _serialFor<T>(String key, Future<T> Function() action) {
    final previous = _writes[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _writes[key] = tail;
    tail.then((_) {
      if (identical(_writes[key], tail)) _writes.remove(key);
    });
    return result;
  }

  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/drafts/$_scope');
    await dir.create(recursive: true);
    return dir;
  }

  /// 捕获不可变快照，异步上传完成或用户重排不会改写已排队的内容。
  Future<void> save({
    required String feeling,
    required int? mood,
    required List<DraftPhotoItem> items,
  }) {
    final snapshot = List<DraftPhotoItem>.of(items);
    return _serialized(() async {
      final dir = await _directory();
      final serialized = <Map<String, dynamic>>[];
      for (final item in snapshot) {
        if (!item.isLocal) {
          serialized.add(item.toJson());
          continue;
        }
        final file = item.file;
        if (file == null) throw const FileSystemException('草稿图片不存在');
        final target = await _persistFile(file, dir);
        serialized.add(item.toJson(fileName: _fileName(target)));
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        _key,
        jsonEncode({
          'version': 2,
          'owner_id': userId,
          'feeling': feeling,
          'mood': mood,
          'items': serialized,
        }),
      );
      if (!saved) throw StateError('无法保存草稿');
      await _removeOwnedLegacy(prefs);
      // 编辑器/上传任务仍可能持有旧文件引用，仅 clear 时清理，绝不按序号覆盖。
    });
  }

  Future<DraftData?> load() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key);
    var legacy = false;
    if (raw == null) {
      raw = prefs.getString('draft_$dateStr');
      legacy = true;
    }
    if (raw == null) return null;
    return _decodeDraft(raw, legacy: legacy);
  });

  /// 只提供给页面的明确恢复操作，绝不在 load 中自动认领无归属旧数据。
  Future<DraftData?> loadLegacyForRecovery() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('draft_$dateStr');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['owner_id'] != null ||
          data['author_id'] != null) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return _decodeDraft(raw, legacy: true, allowUnowned: true);
  });

  /// 账号间共用旧草稿认领队列，确认与新清单提交成功后才移除旧记录。
  Future<void> recoverLegacy(DraftData draft) =>
      _serialFor('legacy_$dateStr', () async {
        final prefs = await SharedPreferences.getInstance();
        final source = draft._legacySource;
        if (source == null || prefs.getString('draft_$dateStr') != source) {
          throw StateError('旧草稿已发生变化，请重新打开编辑页');
        }
        await save(
          feeling: draft.feeling,
          mood: draft.mood,
          items: draft.photoItems,
        );
        if (prefs.getString('draft_$dateStr') == source) {
          if (!await prefs.remove('draft_$dateStr')) {
            throw StateError('清理旧草稿记录失败');
          }
        }
      });

  Future<DraftData?> _decodeDraft(
    String raw, {
    required bool legacy,
    bool allowUnowned = false,
  }) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!allowUnowned &&
          data['owner_id'] != userId &&
          data['author_id'] != userId) {
        return null;
      }
      final dir = legacy
          ? Directory(
              '${(await getApplicationDocumentsDirectory()).path}/drafts',
            )
          : await _directory();
      final result = <DraftPhotoItem>[];
      final rawItems = data['items'];
      if (rawItems is List) {
        for (final value in rawItems) {
          if (value is! Map<String, dynamic>) continue;
          final name = value['file_name'];
          final index = value['local_index'];
          final String? safeName = name is String && _isFileName(name)
              ? name
              : legacy && index is int && index >= 0
              ? '${dateStr}_img_$index.jpg'
              : null;
          final item = DraftPhotoItem.fromJson(
            value,
            file: safeName == null ? null : File('${dir.path}/$safeName'),
          );
          if (!item.isLocal ||
              (item.file != null && await item.file!.exists())) {
            result.add(item);
          }
        }
      } else if (legacy) {
        final files = <int, File>{};
        if (await dir.exists()) {
          await for (final entry in dir.list()) {
            if (entry is! File) continue;
            final match = RegExp('^${dateStr}_img_(\\d+)\\.jpg\$')
                .firstMatch(_fileName(entry));
            if (match != null) files[int.parse(match.group(1)!)] = entry;
          }
        }
        final indexes = files.keys.toList()..sort();
        for (final index in indexes) {
          result.add(
            DraftPhotoItem(
              isLocal: true,
              file: files[index],
              isMotion: _legacyValue(data, 'live_flags', index) == true,
              uploadLive: _legacyValue(data, 'live_flags', index) == true,
              uploadedUrl: _legacyValue(data, 'uploaded', index) as String?,
              uploadedLive: _legacyValue(data, 'uploaded_live', index) as bool?,
            ),
          );
        }
      }
      return DraftData._(
        data['feeling'] as String? ?? '',
        data['mood'] as int?,
        result,
        allowUnowned ? raw : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 选图后先取得受管理的稳定路径，页面和上传任务从此使用同一个文件。
  Future<File> importImage(File image) => _serialized(() async {
    return _persistFile(image, await _directory());
  });

  Future<File> _persistFile(File image, Directory dir) async {
    if (!await image.exists()) {
      throw FileSystemException('草稿图片不存在，保留上一次完整草稿', image.path);
    }
    final ownName = image.parent.absolute.path == dir.absolute.path
        ? _fileName(image)
        : null;
    final stat = await image.stat();
    final sourceKey =
        '${image.path}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    final names = _sourceNames.putIfAbsent(_key, () => {});
    final name = ownName ?? names[sourceKey] ?? _newName('photo');
    final target = File('${dir.path}/$name');
    if (ownName == null && !await target.exists()) {
      final tmp = File('${target.path}.pending');
      try {
        await image.copy(tmp.path);
        await tmp.rename(target.path);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }
    names[sourceKey] = name;
    return target;
  }

  Future<void> clear() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key)) throw StateError('无法清除草稿');
    await _removeOwnedLegacy(prefs);
    _sourceNames.remove(_key);
    final dir = await _directory();
    // 只删除当前账号、当前日期的文件，不接触未归属旧草稿。
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // 清单已清除，文件删除失败不会恢复已发布草稿。
    }
  });

  Future<File> createStillImage(File motionFile) => _serialized(() async {
    final dir = await _directory();
    return MotionPhotoHelper.extractStillImageTo(
      motionFile,
      File('${dir.path}/${_newName('still')}'),
    );
  });

  static Future<void> transferToMomentCache(
    List<DraftPhotoItem> items,
    List<String> finalImageUrls,
  ) async {
    final cache = PrivateImageCache();
    for (final item in items) {
      final file = item.file;
      final url = item.uploadedUrl;
      if (!item.isLocal ||
          file == null ||
          url == null ||
          !finalImageUrls.contains(url)) {
        continue;
      }
      try {
        await cache.putFile(
          url,
          await file.readAsBytes(),
          fileExtension: 'jpg',
        );
      } on FileSystemException {
        // 缓存是可选优化，远端保存成功不应被本地缓存失败回滚。
      }
    }
  }

  Future<void> _removeOwnedLegacy(SharedPreferences prefs) async {
    final raw = prefs.getString('draft_$dateStr');
    if (raw == null) return;
    try {
      final legacy = jsonDecode(raw);
      if (legacy is Map &&
          (legacy['owner_id'] == userId || legacy['author_id'] == userId)) {
        await prefs.remove('draft_$dateStr');
      }
    } on FormatException {
      // 未归属或损坏旧草稿不自动认领和删除。
    }
  }

  static dynamic _legacyValue(
    Map<String, dynamic> data,
    String key,
    int index,
  ) {
    final map = data[key];
    return map is Map ? map['$index'] : null;
  }

  static String _newName(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}.jpg';

  static bool _isFileName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\');

  static String _fileName(File file) =>
      file.path.split(Platform.pathSeparator).last.split('/').last;
}

/// 排序、实况开关、上传进度与同一张照片一起持久化，避免按序号错配。
class DraftPhotoItem {
  final bool isLocal;
  final String? url;
  final File? file;
  final bool isMotion;
  final bool uploadLive;
  final String? uploadedUrl;
  final bool? uploadedLive;

  const DraftPhotoItem({
    required this.isLocal,
    this.url,
    this.file,
    this.isMotion = false,
    this.uploadLive = false,
    this.uploadedUrl,
    this.uploadedLive,
  });

  Map<String, dynamic> toJson({String? fileName}) => {
    'type': isLocal ? 'local' : 'remote',
    if (isLocal && fileName != null) 'file_name': fileName,
    if (!isLocal && url != null) 'url': url,
    'is_motion': isMotion,
    'upload_live': uploadLive,
    if (isLocal && uploadedUrl != null) 'uploaded_url': uploadedUrl,
    if (isLocal && uploadedLive != null) 'uploaded_live': uploadedLive,
  };

  factory DraftPhotoItem.fromJson(Map<String, dynamic> json, {File? file}) =>
      DraftPhotoItem(
        isLocal: json['type'] != 'remote',
        url: json['url'] as String?,
        file: file,
        isMotion: json['is_motion'] as bool? ?? false,
        uploadLive: json['upload_live'] as bool? ?? false,
        uploadedUrl: json['uploaded_url'] as String?,
        uploadedLive: json['uploaded_live'] as bool?,
      );
}

class DraftData {
  final String feeling;
  final int? mood;
  final List<DraftPhotoItem> photoItems;
  final String? _legacySource;

  const DraftData._(
    this.feeling,
    this.mood,
    this.photoItems,
    this._legacySource,
  );
}
