import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/app_theme.dart';
import '../models/moment.dart';
import '../utils/date_helper.dart';
import 'avatar_widget.dart';

/// 朋友圈风格动态卡片
/// 展示：头像 + 昵称 + 自己的图 + 对方的图 + 感受文字 + 时间
class MomentCard extends StatelessWidget {
  final Moment moment;
  final String nickname;
  final String? avatarUrl;

  const MomentCard({
    super.key,
    required this.moment,
    this.nickname = '',
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.cardColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像 + 昵称
          Row(
            children: [
              AvatarWidget(
                avatarUrl: avatarUrl,
                nickname: nickname,
                size: 32,
              ),
              const SizedBox(width: 8),
              Text(nickname, style: AppTheme.momentNickname),
            ],
          ),
          const SizedBox(height: 10),

          // 两张图片：上下排列
          _buildImageBox(context, moment.selfImageUrl, ''),
          const SizedBox(height: 6),
          _buildImageBox(context, moment.partnerImageUrl, ''),
          const SizedBox(height: 10),

          // 感受文字
          if (moment.feeling.isNotEmpty)
            Text(moment.feeling, style: AppTheme.momentContent),

          const SizedBox(height: 8),

          // 时间
          Text(
            DateHelper.toShortTime(moment.updatedAt),
            style: AppTheme.momentTime,
          ),
        ],
      ),
    );
  }

  Widget _buildImageBox(BuildContext context, String url, String label) {
    final image = url.isNotEmpty
        ? GestureDetector(
            onTap: () => _openFullScreen(context, url),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => _placeholder(label),
            ),
          )
        : _placeholder(label);

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  void _openFullScreen(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImage(url: url),
      ),
    );
  }

  Widget _placeholder(String label) {
    return Container(
      color: Colors.grey[100],
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 28, color: Colors.grey[300]),
          if (label.isNotEmpty)
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ),
    );
  }
}

/// 全屏图片查看器：支持缩放 + 下载
class _FullScreenImage extends StatefulWidget {
  final String url;
  const _FullScreenImage({required this.url});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage> {
  bool _isDownloading = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final res = await http.get(Uri.parse(widget.url));
      final dir = await getApplicationDocumentsDirectory();
      final name = widget.url.split('/').last;
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(res.bodyBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            tooltip: '下载',
            onPressed: _isDownloading ? null : _download,
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: SizedBox.expand(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (_, e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, size: 48, color: Colors.white54),
                  const SizedBox(height: 8),
                  const Text('图片加载失败', style: TextStyle(color: Colors.white54)),
                  Text('$e', style: const TextStyle(color: Colors.white30, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
