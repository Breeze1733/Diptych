# Split Moments

## 功能

- 🔐 **密钥登录** — 双方各持独立密钥，本地验证
- 📅 **日历视图** — 按日期浏览历史记录
- 📷 **双人日记** — 每天各写一条，两张照片 + 一段感受
- 🔒 **隐私优先** — 仅双方可见，数据自托管

## 技术栈

| 层 | 技术 |
|---|------|
| 前端 | Flutter 3.44+ / Dart 3.12+ |
| 状态管理 | Riverpod |
| 后端 | 自建 REST API（见 [API 文档](docs/backend-api-spec.md)） |

## 开始

### 环境要求

- Flutter SDK ≥ 3.44
- Android SDK Platform 36 + Build-Tools 36
- JDK 17

### 安装依赖

```bash
flutter pub get
```

### 构建 APK

```bash
# Debug 版本（开发调试用）
flutter build apk --debug

# Release 版本（正式发布用）
flutter build apk --release

# 分架构构建（减小体积）
flutter build apk --split-per-abi
```

产物路径：`build/app/outputs/flutter-apk/app-debug.apk`

### 安装到手机

```bash
# USB 连接手机后
flutter install

# 或者用 adb
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 本地运行（热重载开发）

```bash
# Android 真机
flutter run -d <device-id>

# Chrome 浏览器
flutter run -d chrome
```

查看已连接设备：`flutter devices`

## 项目结构

```
lib/
├── main.dart              # 入口
├── app.dart               # 根组件（认证路由）
├── config/                # 配置（密钥等）
├── constants/             # 常量（字符串、主题）
├── models/                # 数据模型
│   ├── app_user.dart
│   └── moment.dart
├── providers/             # Riverpod Provider
│   ├── auth_provider.dart
│   ├── day_moment_provider.dart
│   └── selected_date_provider.dart
├── screens/               # 页面
│   ├── login_screen.dart
│   ├── feed_screen.dart
│   └── edit_moment_screen.dart
├── services/              # 服务层
│   ├── api_service.dart       # REST API 调用
│   ├── auth_service.dart      # 本地认证
│   └── storage_service.dart   # 图片上传
├── utils/                 # 工具
│   └── date_helper.dart
└── widgets/               # 组件
    ├── avatar_widget.dart
    ├── calendar_picker.dart
    ├── date_header.dart
    ├── day_split_view.dart
    ├── image_slot.dart
    └── moment_card.dart
```

## 常见问题

### 构建卡住或超时

国内网络访问 Gradle/Maven 仓库可能很慢。项目已配置阿里云镜像，如仍需代理：

1. 确保代理软件已启动（如 Clash）
2. 检查 `android/gradle.properties` 中代理端口是否正确

### 图片上传失败

需确保后端 `POST /api/upload` 接口可正常访问，详见 [API 文档](docs/backend-api-spec.md)。


每次都改两处，同一个版本号：

文件	改什么	示例
pubspec.yaml:4	version: x.y.z+N	version: 1.0.2+3
version.json	version + version_code	"version": "1.0.2", "version_code": 3

重启后端
pm2 restart moments-backend

## License

MIT
