# Diptych

> 双人私密日记 — 两个人，各自的视角，一起的日子。

Diptych 是一款为两人设计的私密日记 App。每天双方各记一条，包含照片、心情分和文字；主界面以左右分屏形式同时展示两人当日的内容，像一幅双联画（Diptych）。

**仅支持 Android。数据存储于自托管后端，不经过任何第三方云服务。**

---

## 功能

- **密钥登录** — 双方各持独立密钥，本地验证，无账号体系
- **每日双联** — 每天各写一条日记，附照片（多图）、心情分（1–10）、文字感受
- **左右分屏** — 主界面同时展示两人当日内容，随时浏览对方的记录
- **互动评论** — 在对方（或自己）的日记下留言、回复，支持多级嵌套
- **日历视图** — 按日期跳转历史，有日记的日期显示小圆点标记
- **话题广场** — 发起/参与话题讨论，不限于当日内容
- **离线可用** — 本地缓存策略：已读内容断网也能查看，后台静默同步
- **应用内更新** — 自动检测新版本并下载安装（Android APK）
- **头像裁剪** — 支持自定义头像，带裁剪功能

---

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter 3.x / Dart 3.12+ |
| 状态管理 | [Riverpod](https://riverpod.dev/) 2.x |
| 网络 | `package:http` — REST API |
| 图片缓存 | `cached_network_image` + `flutter_cache_manager` |
| 本地存储 | `shared_preferences`（缓存 + 登录态 + 草稿元数据） |
| 图片选择/裁剪 | `image_picker` + `image_cropper` |
| 日历 | `table_calendar` |
| 版本检测 | `package_info_plus` + `open_filex` |

---

## 项目结构

```
lib/
├── main.dart                  # 入口，启动时清理旧安装包
├── app.dart                   # 根组件，根据登录状态路由
├── constants/
│   ├── app_theme.dart         # 全局主题（颜色、文字样式）
│   └── strings.dart           # 中文字符串常量
├── models/
│   ├── app_user.dart          # 用户模型（uid / nickname / avatarUrl）
│   ├── moment.dart            # 日记模型（含评论 Comment）
│   └── topic.dart             # 话题 / 帖子模型
├── providers/
│   ├── auth_provider.dart     # 认证状态、用户数据加载
│   ├── day_moment_provider.dart   # 当日日记（缓存优先 + 后台刷新）
│   └── selected_date_provider.dart
├── screens/
│   ├── login_screen.dart
│   ├── feed_screen.dart       # 主页（分屏 + 日历 + 评论逻辑）
│   ├── edit_moment_screen.dart
│   ├── profile_screen.dart
│   ├── topics_screen.dart
│   └── topic_detail_screen.dart
├── services/
│   ├── api_service.dart       # REST API 调用（用户、日记）
│   ├── auth_service.dart      # 密钥验证 + SharedPreferences 持久化
│   ├── cache_service.dart     # 日记 / 用户 / 日历圆点本地缓存
│   ├── draft_service.dart     # 草稿（文本 + 图片文件）
│   ├── storage_service.dart   # 图片上传
│   ├── topic_service.dart     # 话题 REST API
│   └── update_service.dart    # 版本检测与 APK 下载安装
├── utils/
│   ├── cache_helper.dart      # 缓存大小计算与清理
│   ├── date_helper.dart       # 日期格式化工具
│   ├── file_helper.dart       # 文件工具
│   └── url_helper.dart        # 相对路径转完整 URL
└── widgets/
    ├── avatar_widget.dart
    ├── calendar_picker.dart
    ├── date_header.dart
    ├── day_split_view.dart    # 左右分屏容器
    ├── image_gallery.dart
    ├── moment_card.dart       # 单条日记卡片（含评论树）
    └── photo_grid_picker.dart
```

---

## 构建与运行

### 环境要求

- Flutter SDK ≥ 3.12（运行 `flutter --version` 确认）
- Android SDK Platform 36 + Build-Tools 36
- JDK 17

### 配置密钥

在 `lib/constants/` 下创建 `secrets.dart`（已在 `.gitignore` 中排除，不会提交）：

```dart
class Secrets {
  static String? validateKey(String key) {
    const keys = {'<用户A的密钥>': 'A', '<用户B的密钥>': 'B'};
    return keys[key];
  }
}
```

### 安装依赖

```bash
flutter pub get
```

### 本地运行（调试）

```bash
flutter run
```

### 构建 Release APK

```bash
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

---

## 后端

App 对接自托管 REST API，基础地址为 `https://example.com/api`。后端代码不在本仓库中。

如需对接自己的后端，修改以下文件中的 `_baseUrl` 或 `baseUrl` 常量：

- [lib/services/api_service.dart](lib/services/api_service.dart)
- [lib/services/storage_service.dart](lib/services/storage_service.dart)
- [lib/services/topic_service.dart](lib/services/topic_service.dart)
- [lib/services/update_service.dart](lib/services/update_service.dart)
- [lib/utils/url_helper.dart](lib/utils/url_helper.dart)

---

## License

MIT
