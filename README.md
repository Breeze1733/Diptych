<div align="center">

<img src="assets/icon.png" alt="Diptych" width="96" height="96" />

# Diptych

双联画，各自的视角，共同的日子。

><div align="left">
>Diptych 是一款专为两人设计的日记 App。每天双方各记一条日记，包含照片、心情分与文字感受；主界面以左右分屏同时展示两人的当日内容，如同一幅双联画 —— Diptych。
></div>

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)]()
[![Dart](https://img.shields.io/badge/Dart-3.12%2B-0175C2?style=flat-square&logo=dart&logoColor=white)]()
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)]()
[![Version](https://img.shields.io/badge/Version-1.1.5-4B8BBE?style=flat-square)]()
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)]()
[![Repo Size](https://img.shields.io/github/repo-size/Breeze1733/Diptych?style=flat-square&label=repo%20size)]()
[![Last Commit](https://img.shields.io/github/last-commit/Breeze1733/Diptych?style=flat-square&label=last%20commit)]()

</div>

## 预览

<div align="center">
  <img src="assets/homepage.png" width="30%" alt="软件主页" />
  &nbsp;&nbsp;&nbsp;
  <img src="assets/moment.png" width="30%" alt="分屏日记" />
  &nbsp;&nbsp;&nbsp;
  <img src="assets/topic.png" width="30%" alt="话题广场" />
  <br/>
  <em>软件主页 · 分屏日记 · 话题广场</em>
</div>

---

## 目录

- [预览](#预览)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
  - [环境要求](#环境要求)
  - [获取代码](#获取代码)
  - [配置密钥](#配置密钥)
  - [配置后端地址](#配置后端地址)
  - [安装依赖](#安装依赖)
  - [本地运行](#本地运行)
  - [构建 Release APK](#构建-release-apk)
- [隐私与数据](#隐私与数据)
- [贡献指南](#贡献指南)
- [License](#license)

## 功能特性

- 🔐 **密钥登录** — 双方各持独立密钥，本地验证，无账号体系、无第三方登录
- 🖼️ **每日双联** — 每天各写一条日记，支持多图照片、心情分（1–10）与文字感受
- ↔️ **左右分屏** — 主界面同时呈现两人当日内容，随时回看对方的记录
- 💬 **互动评论** — 在对方（或自己）的日记下留言、回复，支持多级嵌套
- 📅 **日历视图** — 按日期跳转历史，已记录的日期以小圆点标记
- 🗂️ **话题广场** — 发起 / 参与话题讨论，不局限于当日内容
- 🎨 **壁纸与视觉定制** — 支持日记主页与话题广场自定义壁纸，自由调节模糊度与透明度，提供全屏实时预览与区域调整
- 📤 **智能上传与画廊预览** — 选图即触发后台异步上传，支持状态感知（等待/上传中/重试）、断点续传与全屏手势大图预览/缩放/删除
- 🛡️ **草稿防丢与容灾机制** — 自动持久化草稿文字与已上传图片 URL 映射，异常退出或发布失败时不丢进度、不重复上传
- 🔋 **前台保活与 WakeLock** — 引入 Android 前台常驻通知服务与系统级 CPU/屏幕唤醒锁，防止大文件传输与后台下载被系统休眠中断
- ⚡ **满速断点下载更新** — 集成系统级满速多线程/分块断点续传下载引擎，支持通知栏与应用内进度实时展示，下载完毕自动触发安装
- 📡 **离线可用** — 本地多级缓存策略：已读内容断网也能查看，网络恢复后静默同步
- ✂️ **头像裁剪** — 支持自定义头像，内置多比例裁剪功能

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter 3.x / Dart 3.12+ |
| 状态管理 | [Riverpod](https://riverpod.dev/) 3.x (`flutter_riverpod 3.4.2`) |
| 网络与传输 | `package:http` — REST API + 分片断点上传 |
| 图片缓存 | `cached_network_image` + `flutter_cache_manager` |
| 本地存储 | `shared_preferences`（缓存 + 登录态 + 草稿与上传状态元数据） |
| 图片选择 / 裁剪 / 预览 | `image_picker` + `image_cropper` + `photo_view` |
| 日历 | `table_calendar` |
| 版本更新与下载 | `package_info_plus` + `open_filex` + 系统级满速断点下载引擎 |
| 传输保活 | Android Foreground Service（前台通知服务） + WakeLock 唤醒锁 |

## 项目结构

```
lib/
├── main.dart                  # 入口，启动时清理旧安装包与初始化
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
│   ├── selected_date_provider.dart
│   └── wallpaper_provider.dart    # 背景壁纸与透明度/模糊度状态
├── screens/
│   ├── login_screen.dart
│   ├── feed_screen.dart       # 主页（分屏 + 日历 + 评论逻辑）
│   ├── edit_moment_screen.dart # 日记编辑（异步上传 + 断点续传 + 容灾）
│   ├── profile_screen.dart    # 个人中心（设置 / 更新 / 缓存清理）
│   ├── topics_screen.dart     # 话题列表
│   ├── topic_detail_screen.dart # 话题详情与互动
│   ├── topic_post_screen.dart # 话题发布（图片预览 + 异步上传）
│   ├── wallpaper_settings_screen.dart # 壁纸参数配置
│   ├── wallpaper_preview_screen.dart  # 壁纸全屏实时效果预览
│   └── wallpaper_zoom_screen.dart     # 壁纸缩放与区域调整
├── services/
│   ├── api_service.dart       # REST API 调用（用户、日记）
│   ├── auth_service.dart      # 密钥验证 + SharedPreferences 持久化
│   ├── cache_service.dart     # 日记 / 用户 / 日历圆点本地缓存
│   ├── draft_service.dart     # 草稿（文本 + 本地与已上传图片元数据）
│   ├── storage_service.dart   # 图片上传与分片断点续传
│   ├── topic_service.dart     # 话题 REST API
│   └── update_service.dart    # 版本检测与 APK 满速断点下载安装
├── utils/
│   ├── cache_helper.dart      # 缓存大小计算与清理
│   ├── date_helper.dart       # 日期格式化工具
│   ├── file_helper.dart       # 文件工具
│   ├── foreground_service_helper.dart # Android 前台保活服务通信通道
│   ├── url_helper.dart        # 相对路径转完整 URL
│   └── wakelock_helper.dart   # 屏幕与 CPU WakeLock 保活
└── widgets/
    ├── avatar_widget.dart
    ├── calendar_picker.dart
    ├── date_header.dart
    ├── day_split_view.dart    # 左右分屏容器
    ├── image_gallery.dart     # 全屏图片手势画廊与预览查看器
    ├── moment_card.dart       # 单条日记卡片（含评论树）
    ├── photo_grid_picker.dart # 九宫格图片选择器（实时上传状态徽标）
    └── wallpaper_layer.dart   # 全局/局部壁纸背景渲染层
```

## 快速开始

### 环境要求

- Flutter SDK ≥ 3.12（运行 `flutter --version` 确认）
- Android SDK Platform 36 + Build-Tools 36
- JDK 17

### 获取代码

```bash
git clone https://github.com/Breeze1733/Diptych.git
cd Diptych
```

### 配置密钥

在 `lib/constants/` 下创建 `secrets.dart`（该文件已在 `.gitignore` 中排除，不会提交到仓库）：

```dart
class Secrets {
  Secrets._();

  /// 用户 A 的密钥
  static const String keyA = '<用户A的密钥>';

  /// 用户 B 的密钥
  static const String keyB = '<用户B的密钥>';

  /// 验证密钥，返回用户角色，无效返回 null
  static String? validateKey(String key) {
    if (key == keyA) return 'A';
    if (key == keyB) return 'B';
    return null;
  }
}
```

> 登录时通过 `Secrets.validateKey()` 校验密钥，仓库内不包含任何真实密钥。

### 配置后端地址

App 对接自托管 REST API，后端代码不在本仓库中。在 `lib/constants/` 下创建 `api_config.dart`（该文件已在 `.gitignore` 中排除，不会提交到仓库）：

```dart
class ApiConfig {
  ApiConfig._();

  /// 站点根地址（用于拼接图片等相对路径）
  static const String siteUrl = '<你的站点根地址>';

  /// REST API 基础地址
  static const String apiBaseUrl = '$siteUrl/api';
}
```

> 全部网络请求均通过 `ApiConfig.apiBaseUrl` / `ApiConfig.siteUrl` 读取地址，无需逐个修改，仓库内不包含任何实际后端地址。

### 安装依赖

```bash
flutter pub get
```

### 本地运行

```bash
flutter run
```

### 构建 Release APK

```bash
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

## 隐私与数据

- 🔒 **数据自持** — 日记、图片与话题数据全部存储于自托管后端，不经过任何第三方云服务
- 🔑 **密钥本地验证** — 登录密钥仅在本机校验，无账号体系，不上传账号信息
- 📴 **离线可读** — 已缓存的内容在断网时仍可浏览

## 贡献指南

欢迎提交 Issue 与 Pull Request！

- **发现问题**：请先搜索是否已有类似 [Issue](https://github.com/Breeze1733/Diptych/issues)，若无则新建并描述复现步骤与设备信息
- **提交代码**：Fork 仓库 → 基于 `main` 分支新建特性分支 → 提交 PR，请确保代码通过 `flutter analyze` 检查
- **代码风格**：遵循 `analysis_options.yaml` 中的 `flutter_lints` 规则

## License

[MIT](./LICENSE)

Copyright © 2026 Breeze1733
