import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../constants/app_theme.dart';

/// 壁纸缩放预览页：只支持放缩（双指缩放 + 拖动），无旋转、无裁剪。
///
/// 图片以「铺满屏幕」的比例初始展示，用户双指缩放 / 拖动调整构图，
/// 确认后原图上传（展示时按页面实际比例 BoxFit.cover 自适应裁剪）。
class WallpaperZoomScreen extends StatefulWidget {
  final File file;

  const WallpaperZoomScreen({super.key, required this.file});

  @override
  State<WallpaperZoomScreen> createState() => _WallpaperZoomScreenState();
}

class _WallpaperZoomScreenState extends State<WallpaperZoomScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('调整壁纸', style: TextStyle(fontSize: 16)),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoView(
              imageProvider: FileImage(widget.file),
              // 初始铺满屏幕，最小可缩到铺满，最大放大 4 倍
              initialScale: PhotoViewComputedScale.covered,
              minScale: PhotoViewComputedScale.covered,
              maxScale: PhotoViewComputedScale.covered * 4.0,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              filterQuality: FilterQuality.high,
            ),
          ),
          // 底部提示 + 完成
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '双指缩放，拖动调整位置',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      minimumSize: const Size(200, 44),
                    ),
                    onPressed: () => Navigator.pop(context, widget.file),
                    child: const Text('完成',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
