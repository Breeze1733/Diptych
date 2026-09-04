import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 实况照片（Motion Photo / 动态照片）解析与提取工具类
///
/// 兼容小米（MIUI / 澎湃 HyperOS）、荣耀（MagicOS / 华为体系）、Google Pixel、三星等
/// 将内嵌在单个 JPEG 尾部的 MP4 视频流高速解析、提取并就地缓存。
class MotionPhotoHelper {
  MotionPhotoHelper._();

  /// 内存解析缓存：文件路径 -> 提取出的临时 MP4 视频文件 (null 表示非实况图)
  static final Map<String, File?> _memoryCache = {};

  /// 检查指定本地文件是否为实况照片（极速二进制检索，无需解压视频）
  static Future<bool> isMotionPhoto(File? file) async {
    if (file == null || !await file.exists()) return false;
    final path = file.path;
    if (_memoryCache.containsKey(path)) {
      return _memoryCache[path] != null;
    }
    try {
      final length = await file.length();
      if (length < 100 * 1024) return false;
      final mp4Offset = await _findMp4Offset(file, length);
      return mp4Offset > 0;
    } catch (_) {
      return false;
    }
  }

  /// 提取纯静态 JPEG 图片（无损剥离尾部 MP4 视频流）
  ///
  /// 如果文件不是实况照片，返回原文件；如果是实况照片，切片提取前半部分纯静态 JPEG。
  static Future<File> getOrExtractStillImage(File file) async {
    final path = file.path;
    if (!await file.exists()) return file;

    try {
      final length = await file.length();
      if (length < 100 * 1024) return file;

      final mp4Offset = await _findMp4Offset(file, length);
      if (mp4Offset <= 0) return file;

      File targetFile = File('${path}_still.jpg');
      try {
        if (await targetFile.exists()) {
          final existingSize = await targetFile.length();
          if (existingSize == mp4Offset) return targetFile;
        }
      } catch (_) {
        targetFile = File('${Directory.systemTemp.path}/${path.hashCode}_still.jpg');
      }

      final raf = await file.open(mode: FileMode.read);
      RandomAccessFile? outRaf;
      try {
        try {
          outRaf = await targetFile.open(mode: FileMode.write);
        } catch (_) {
          targetFile = File('${Directory.systemTemp.path}/${path.hashCode}_still.jpg');
          outRaf = await targetFile.open(mode: FileMode.write);
        }

        const chunkSize = 256 * 1024;
        int bytesLeft = mp4Offset;
        while (bytesLeft > 0) {
          final toRead = bytesLeft > chunkSize ? chunkSize : bytesLeft;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;
          await outRaf.writeFrom(chunk);
          bytesLeft -= chunk.length;
        }
      } finally {
        await raf.close();
        await outRaf?.close();
      }

      return targetFile;
    } catch (e) {
      return file;
    }
  }

  /// 获取或提取实况照片的 MP4 视频文件
  ///
  /// 如果存在内嵌 MP4，则返回对应的 .mp4 文件；如果是普通静态图，返回 null。
  static Future<File?> getOrExtractMotionVideo(File file) async {
    final path = file.path;
    if (_memoryCache.containsKey(path)) {
      final cachedFile = _memoryCache[path];
      if (cachedFile != null && await cachedFile.exists()) {
        return cachedFile;
      }
    }

    try {
      final length = await file.length();
      // 一般实况照片的内嵌视频至少在 500KB 以上，文件过小直接跳过
      if (length < 100 * 1024) {
        _memoryCache[path] = null;
        return null;
      }

      // 目标视频缓存文件路径
      final videoPath = '${path}_motion.mp4';
      final targetVideoFile = File(videoPath);

      // 1. 查找 MP4 文件头特征 'ftyp'
      final mp4Offset = await _findMp4Offset(file, length);
      if (mp4Offset == -1) {
        _memoryCache[path] = null;
        return null;
      }

      final expectedVideoSize = length - mp4Offset;
      if (expectedVideoSize <= 0) {
        _memoryCache[path] = null;
        return null;
      }

      // 如果已存在且大小一致，直接复用
      if (await targetVideoFile.exists()) {
        final existingSize = await targetVideoFile.length();
        if (existingSize == expectedVideoSize) {
          _memoryCache[path] = targetVideoFile;
          return targetVideoFile;
        }
      }

      // 2. 从原图切割后半段 MP4 字节流并保存
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(mp4Offset);
        final mp4Bytes = await raf.read(expectedVideoSize);
        await targetVideoFile.writeAsBytes(mp4Bytes, flush: true);
      } finally {
        await raf.close();
      }

      _memoryCache[path] = targetVideoFile;
      return targetVideoFile;
    } catch (e) {
      // 容错：解析失败不影响普通看图
      return null;
    }
  }

  /// 将实况照片自适应注入目标设备（如荣耀 MagicOS 或小米 HyperOS）的 XMP 元数据，保存到目标文件
  static Future<void> saveAdaptedMotionPhoto(
    File sourceFile,
    File destinationFile, {
    String? targetManufacturer,
  }) async {
    try {
      final length = await sourceFile.length();
      final mp4Offset = await _findMp4Offset(sourceFile, length);

      // 如果不是实况图，直接复制原始文件
      if (mp4Offset == -1) {
        await sourceFile.copy(destinationFile.path);
        return;
      }

      final bytes = await sourceFile.readAsBytes();
      final jpegBytes = bytes.sublist(0, mp4Offset);
      final mp4Bytes = bytes.sublist(mp4Offset);
      final videoLength = mp4Bytes.length;

      // 判断目标机型
      final m = (targetManufacturer ?? '').toLowerCase();
      final isHonorOrHuawei = m.contains('honor') || m.contains('huawei');

      // 构造精准适配目标机型的 XMP 描述内容
      final String xmpXml;
      if (isHonorOrHuawei) {
        xmpXml =
            '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
            '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
            '<rdf:Description rdf:about="" '
            'xmlns:HwCamera="http://ns.huawei.com/camera/1.0/" '
            'HwCamera:MovingPhoto="1" '
            'HwCamera:MovingPhotoVersion="1" '
            'HwCamera:MovingPhotoOffset="$videoLength" '
            'xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
            'GCamera:MotionPhoto="1" '
            'GCamera:MotionPhotoVersion="1" '
            'GCamera:MicroVideo="1" '
            'GCamera:MicroVideoVersion="1" '
            'GCamera:MicroVideoOffset="$videoLength"/>'
            '</rdf:RDF>'
            '</x:xmpmeta>';
      } else {
        // 小米 / Redmi / Google / 通用规范
        xmpXml =
            '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
            '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
            '<rdf:Description rdf:about="" '
            'xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
            'GCamera:MotionPhoto="1" '
            'GCamera:MotionPhotoVersion="1" '
            'GCamera:MotionPhotoPresentationTimestampUs="0" '
            'GCamera:MicroVideo="1" '
            'GCamera:MicroVideoVersion="1" '
            'GCamera:MicroVideoOffset="$videoLength" '
            'GCamera:MicroVideoPresentationTimestampUs="0"/>'
            '</rdf:RDF>'
            '</x:xmpmeta>';
      }

      final xmpBytes = utf8.encode(xmpXml);
      // http://ns.adobe.com/xap/1.0/\x00 标准 XMP APP1 命名空间前缀（29 字节）
      final xmpNamespace = [...utf8.encode('http://ns.adobe.com/xap/1.0/'), 0x00];
      final payloadLength = xmpNamespace.length + xmpBytes.length;
      final segmentLength = payloadLength + 2;

      final app1Segment = <int>[
        0xFF, 0xE1, // APP1 marker
        (segmentLength >> 8) & 0xFF,
        segmentLength & 0xFF,
        ...xmpNamespace,
        ...xmpBytes,
      ];

      // 组装新 JPEG：SOI (FF D8) + APP1 Segment + 原始 JPEG 主体 (跳过前 2 字节 SOI) + MP4 视频流
      final builder = BytesBuilder(copy: false);
      if (jpegBytes.length >= 2 && jpegBytes[0] == 0xFF && jpegBytes[1] == 0xD8) {
        builder.add(jpegBytes.sublist(0, 2)); // SOI
        builder.add(app1Segment);
        builder.add(jpegBytes.sublist(2));
      } else {
        builder.add(jpegBytes);
        builder.add(app1Segment);
      }
      builder.add(mp4Bytes);

      await destinationFile.writeAsBytes(builder.takeBytes(), flush: true);
    } catch (_) {
      // 容错兜底：若转译异常则直接复制原图
      await sourceFile.copy(destinationFile.path);
    }
  }

  /// 在 JPEG 文件中查找 MP4 'ftyp' box 的起始偏移量
  ///
  /// MP4 规范：起始 4 字节为 Box Size，紧接 4 字节 ASCII 字符 'ftyp' (0x66, 0x74, 0x79, 0x70)
  static Future<int> _findMp4Offset(File file, int fileLength) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      // 实况视频通常追加在尾部，我们从文件末尾向前检索以获得极佳性能
      // 每次读取 256KB 的数据块
      const chunkSize = 256 * 1024;
      int currentEnd = fileLength;

      // 最多向前检索整个文件
      while (currentEnd > 8) {
        final currentStart = (currentEnd - chunkSize - 8).clamp(0, fileLength);
        final readLength = currentEnd - currentStart;
        await raf.setPosition(currentStart);
        final buffer = await raf.read(readLength);

        // 在当前 buffer 中查找 'ftyp'
        for (int i = buffer.length - 4; i >= 4; i--) {
          if (buffer[i] == 0x66 && // 'f'
              buffer[i + 1] == 0x74 && // 't'
              buffer[i + 2] == 0x79 && // 'y'
              buffer[i + 3] == 0x70) { // 'p'
            final boxSize = (buffer[i - 4] << 24) |
                (buffer[i - 3] << 16) |
                (buffer[i - 2] << 8) |
                buffer[i - 1];

            // MP4 ftyp box 大小通常在 8 到 1024 字节之间
            if (boxSize >= 8 && boxSize <= 1024) {
              final globalOffset = currentStart + (i - 4);
              if (globalOffset + boxSize <= fileLength) {
                return globalOffset;
              }
            }
          }
        }

        if (currentStart == 0) break;
        currentEnd = currentStart + 8; // 保留 8 字节重叠防止边界跨越
      }

      return -1;
    } finally {
      await raf.close();
    }
  }
}
