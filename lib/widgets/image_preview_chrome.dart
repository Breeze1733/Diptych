import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 图片上的操作层淡入淡出，隐藏后不拦截缩放和翻页手势。
class ImagePreviewChrome extends StatelessWidget {
  final bool visible;
  final Widget child;

  const ImagePreviewChrome({
    super.key,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    ),
  );
}

/// 磨砂玻璃只覆盖操作栏，照片仍然铺在栏位下方。
class ImagePreviewGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const ImagePreviewGlass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(35),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withAlpha(32), Colors.white.withAlpha(10)],
          ),
          border: Border.all(color: Colors.white.withAlpha(30), width: .5),
        ),
        child: child,
      ),
    ),
  );
}
