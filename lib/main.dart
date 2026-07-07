import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/update_service.dart';

/// 应用入口
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 清理上次更新的安装包（不阻塞启动）
  UpdateService.cleanupOldApk();

  // 启动应用，包裹 ProviderScope（Riverpod 根节点）
  runApp(
    const ProviderScope(
      child: DiptychApp(),
    ),
  );
}
