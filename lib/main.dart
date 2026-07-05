import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

/// 应用入口
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动应用，包裹 ProviderScope（Riverpod 根节点）
  runApp(
    const ProviderScope(
      child: SplitMomentsApp(),
    ),
  );
}
