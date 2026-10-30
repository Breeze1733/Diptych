<div align="center">

<img src="pic/icon.png" alt="Diptych" width="160" height="160" />

# Diptych

双联画，各自的视角，共同的日子。

><div align="left">
>Diptych 是一款专为两人设计的日记 App。每天双方各记一条日记，包含照片、心情分与文字感受；主界面以左右分屏同时展示两人的当日内容，如同一幅双联画 —— Diptych。
></div>

[![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B?style=flat-square&logo=flutter&logoColor=white)]()
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?style=flat-square&logo=dart&logoColor=white)]()
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)]()
[![Version](https://img.shields.io/badge/Version-1.3.1-4B8BBE?style=flat-square)]()
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)]()
[![Repo Size](https://img.shields.io/github/repo-size/Breeze1733/Diptych?style=flat-square&label=repo%20size)]()
[![Last Commit](https://img.shields.io/github/last-commit/Breeze1733/Diptych?style=flat-square&label=last%20commit)]()

</div>

## 预览

以下为当前界面的示例截图，使用“用户A / 用户B”、示例头像和壁纸展示布局。

<div align="center">
  <img src="pic/diary.png" width="30%" alt="日记页面" />
  &nbsp;&nbsp;&nbsp;
  <img src="pic/topics.png" width="30%" alt="话题页面" />
  &nbsp;&nbsp;&nbsp;
  <img src="pic/settings.png" width="30%" alt="设置页面" />
  <br/>
  <em>日记页面 · 话题页面 · 设置页面</em>
</div>

<br/>

<div align="center">
  <img src="pic/edit-diary.png" width="30%" alt="编辑日记界面" />
  &nbsp;&nbsp;&nbsp;
  <img src="pic/diary-detail.png" width="30%" alt="日记详情页" />
  &nbsp;&nbsp;&nbsp;
  <img src="pic/calendar.png" width="30%" alt="日历统计视图" />
  <br/>
  <em>编辑日记界面 · 日记详情页 · 日历统计视图</em>
</div>

---

## 目录

- [预览](#预览)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [后端接口](#后端接口)
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

- 🔐 **密钥登录** — 双方各持独立口令，由自托管后端验证并签发会话；私有 API 与照片请求携带会话凭据，口令不再编译进 APK
- 🖼️ **每日双联** — 每人每天一条日记，支持多图照片、可选心情分（1–10）与文字感受；默认查看日期以本机时间早上 6:00 为界，凌晨 0:00–5:59 算前一天
- ✍️ **共记模式** — 在具体日期的编辑页可切换为双方共同书写的单页日记，并选择带入当前内容与当天旧双联；A/B 的文字和照片使用固定蓝/粉标识，在对方文字中插入时会无损拆分原段。共记文档与普通日记统一存于 `moments.json`，只有共记记录携带 `type: "shared"`；独立 revision 与乐观锁保证同时提交不会静默覆盖，原双联记录与旧版接口始终保留
- ↔️ **左右分屏** — 主界面同时呈现两人当日内容，随时回看对方的记录
- 💬 **互动评论** — 在对方（或自己）的日记下留言、回复，支持多级嵌套；按单条追加，重试复用评论 ID。发布页等待服务端确认和读回新评论后再关闭，保留阅读位置并展开定位新留言；详情右上角可单独刷新正文与评论
- 📸 **实况照片** — 识别 Android 多厂商 JPEG 中内嵌的 MP4，支持提取、播放与保存时的厂商元数据适配；定制相册多选器提供单张实况开关，开启时上传完整动态图，关闭时提取静态图。当前仓库提供 Android 平台工程
- 📬 **信箱与通知中心** — 初始化通知列表、进入信箱及相关刷新操作时主动拉取日记、评论和话题通知；服务端取出后清空对应队列，客户端保存历史与已读状态。支持未读计数、单条/全部已读、清空信箱和跳转到对应日期或话题
- 📅 **双人日历** — 区分己方、对方与双方都已记录的日期，支持蓝粉双色标记和纸页日历弹窗；优先读取本地日期缓存，加载日记时补充对应日期标记，手动刷新时联网全量同步
- 🔎 **日记搜索** — 搜索双方日记正文与评论，按日期从新到旧返回；支持输入防抖、关键词摘要高亮、游标分页和点击回到对应日期
- 🗂️ **话题广场** — 创建话题、查看讨论、发布纯文字帖子及删除自己的帖子；发帖支持保存和恢复文字草稿；列表接口直接返回最近更新时间，避免逐条获取完整话题
- 🪶 **纸页双联界面** — 暖白、墨蓝与陶土色统一全局风格；底部紧凑切换日记、话题与我的，日期栏紧凑单行；双联页固定一屏，4:3 封面与完整正文在各自纸页内部滚动，底部固定“展开日记与留言”入口。编辑、留言与回复在展开页内完成并更新，心情统一显示分数；双方未记录时左下角悬浮显示写日记入口。写日记以心情、照片、文字三张卡片填满一屏，心情单行排列，照片保留两行六格位置，多余照片与长文字分别在卡片内滚动；顶栏直接提供搜索、信箱和刷新，我的页面保留壁纸设置及检测连通性入口
- 🎨 **壁纸定制** — 日记与话题分别设置壁纸；选图后按 9:16 裁剪，全屏预览提供壁纸与卡片不透明度两个滑动条，卡片不透明度在日记与话题间共用，点击“应用”后保存到本机并同步后端；可一键设为白色背景，该操作仅保存在本机并保留原壁纸，方便恢复
- 📤 **串行预上传与画廊** — 选图即触发后台串行上传，单张图片按 1 MB 分片发送，失败分片和合并请求自动重试；支持上传进度、失败重试、移除和拖拽排序，以及全屏图片预览、缩放和保存；大图铺满预览区域，磨砂透明操作栏可点按图片隐藏或显示
- 🛡️ **草稿与上传结果复用** — 日记草稿按账号和日期隔离，照片使用稳定文件名，串行提交完整清单；保存文字、心情、混合本地/远程图片顺序、实况状态与已上传 URL。恢复时复用已完成的上传；无作者信息的旧草稿需手动确认后恢复。评论与话题帖子也支持文字草稿
- 🪟 **小窗适配** — 在 Flutter 根组件中修正异常的 MediaQuery 顶部/底部 Insets，主页与日记布局根据窗口尺寸缩放
- 🔋 **传输保活** — 上传、图片预缓存和更新下载分别持有保活租约；最后一个任务结束后才停止前台服务和释放 CPU WakeLock，仍运行的任务继续保留通知与进度
- ⚡ **应用内更新** — 启动后静默检查版本，也可在设置中手动检查；通过 Dart HTTP 流下载 APK，网络中断后用 HTTP Range 重连续传，下载完成调起系统安装，下次启动清理旧安装包
- 📡 **缓存优先与离线浏览** — 用户、日记、日历和通知保存到本地，图片使用磁盘缓存；已缓存内容可离线浏览，日记缓存命中后后台刷新。发布、搜索、话题加载和首次获取未缓存内容需要网络
- 🖼️ **上传后直接缓存** — 日记发布成功后，将本地已上传图片写入 DefaultCacheManager，避免查看自己的日记时再次下载同一张图片
- ✂️ **头像裁剪** — 支持自定义头像，内置多比例裁剪功能
- 📶 **网络检测** — 设置页手动发起最多 3 次轻量请求，显示服务器响应耗时的中位数及快/正常/偏慢/很慢分档；支持取消、10 秒重测冷却与超时、限流、Cloudflare 验证及缓存响应识别

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter ≥ 3.47.0 / Dart SDK `^3.13.0`，当前平台工程为 Android |
| 状态管理 | [Riverpod](https://riverpod.dev/) 3.x (`flutter_riverpod 3.4.2`) |
| 网络与传输 | `package:http` — REST API、串行分片上传与局部重试、HTTP Range 下载重连续传 |
| 图片缓存 | `cached_network_image` + `flutter_cache_manager` |
| 本地存储 | `shared_preferences`（日记/通知/日历标记本地缓存 + 登录态 + 草稿与上传状态元数据） |
| 相册与图片选择 | `wechat_assets_picker`（微信风格相册多选） + `image_picker`（拍照） |
| 实况照片与视频流 | 自研 `MotionPhotoHelper` 二进制流提取引擎 + `video_player`（实况播放） |
| 图片预览 / 裁剪 | `photo_view`（微信同款手势缩放与切页） + `image_cropper`（多比例头像裁剪） |
| 日历 | `table_calendar`（定制双人蓝粉双色与日期选择） |
| 窗口与厂商适配 | Flutter MediaQuery Insets 修正与比例缩放；原生 `MethodChannel` 厂商识别、媒体扫描 |
| 本地化 | `flutter_localizations` + `intl`（简体中文本地化） |
| 版本更新与下载 | `package_info_plus` + Dart HTTP 流式下载 + 原生 APK 安装通道（`open_filex` 兜底） |
| 传输保活 | Android Foreground Service（前台通知服务） + CPU PARTIAL_WAKE_LOCK |

## 项目结构

```
lib/
├── main.dart                  # 入口，启动时清理旧安装包与全局初始化
├── app.dart                   # 根组件，根据登录状态路由与小窗 Insets 矫正
├── constants/
│   ├── api_config.dart        # 后端 API 地址配置（git 忽略，创建方式见下文）
│   ├── app_theme.dart         # 纸页双联全局主题（暖白 / 墨蓝 / 陶土色与统一组件）
│   ├── settings_theme.dart    # 设置页兼容入口，复用全局主题
│   └── strings.dart           # 中文字符串常量
├── models/
│   ├── app_notification.dart  # 互动通知模型（日记/评论/话题通知、跳转元数据）
│   ├── app_user.dart          # 用户模型（uid / nickname / avatarUrl）
│   ├── calendar_marked_dates.dart # 日历双人记录状态模型（单人/双人同记）
│   ├── network_diagnostics.dart # 网络检测结果、失败类型及响应耗时分档
│   ├── moment.dart            # 日记与评论模型（图片 URL、心情、正文、回复关系）
│   ├── shared_moment.dart     # 共记文档与带作者归属的文字/图片块、revision
│   └── topic.dart             # 话题 / 帖子模型
├── providers/
│   ├── auth_provider.dart     # 认证状态、用户数据加载
│   ├── day_moment_provider.dart # 当日日记（缓存优先 + 后台刷新 + 日历状态联动）
│   ├── notification_provider.dart # 未读通知计数与通知列表状态管理
│   ├── selected_date_provider.dart # 当前选中的日期状态
│   └── wallpaper_provider.dart # 日记/话题壁纸与透明度，本地优先初始化
├── screens/
│   ├── login_screen.dart      # 密钥登录
│   ├── home_screen.dart       # 底部导航（日记 / 话题 / 我的，保留已访问页面状态）
│   ├── feed_screen.dart       # 双联日记（日期切换、展开阅读、顶栏搜索 / 信箱 / 刷新）
│   ├── diary_search_screen.dart # 日记/评论搜索（高亮摘要、游标分页、日期跳转）
│   ├── shared_diary_editor_screen.dart # 共记块式编辑、原文拆分插入与冲突二次合并
│   ├── shared_diary_reading_screen.dart # 共记单页整页阅读与刷新
│   ├── edit_moment_screen.dart # 日记编辑（草稿/预上传、按日转共记并安全带入内容）
│   ├── notification_screen.dart # 信箱与通知列表（未读标记、跳转上下文、一键已读）
│   ├── profile_screen.dart    # 个人中心（设置 / 网络检测 / 更新 / 缓存清理）
│   ├── topics_screen.dart     # 话题列表
│   ├── topic_detail_screen.dart # 话题详情与互动
│   ├── topic_post_screen.dart # 话题纯文字发帖与草稿
│   ├── wallpaper_settings_screen.dart # 壁纸选图、9:16 裁剪、上传及白色背景设置
│   └── wallpaper_preview_screen.dart # 壁纸全屏预览与透明度调整
├── services/
│   ├── api_service.dart       # REST API（用户、日记、搜索、日历标记、通知）
│   ├── auth_service.dart      # 服务端登录 + 会话恢复与退出
│   ├── auth_session.dart      # 当前会话与账号切换版本校验
│   ├── api_http_client.dart   # 限定来源的 Bearer 请求与会话绑定
│   ├── http_request.dart      # 完整请求超时与连接清理
│   ├── private_image_cache.dart # 沿用磁盘缓存并为私有照片请求鉴权
│   ├── transfer_keep_alive.dart # 多任务前台服务与 WakeLock 租约协调
│   ├── moment_save_service.dart # 提交日记、更新缓存与确认旧资源清理顺序
│   ├── cache_service.dart     # 日记、用户及双人日历状态缓存
│   ├── draft_service.dart     # 按账号隔离的草稿清单、稳定图片及旧草稿恢复
│   ├── notification_service.dart # 通知持久化缓存与服务端队列同步
│   ├── network_diagnostics_service.dart # 轻量网络探测、响应校验、超时与取消
│   ├── storage_service.dart   # 1 MB 分片上传、局部重试、会话校验、合并及删除图片
│   ├── topic_service.dart     # 话题 REST API
│   └── update_service.dart    # 版本检测、APK 流式下载重连续传、安装及清理
├── utils/
│   ├── cache_helper.dart      # 缓存大小计算与清理
│   ├── date_helper.dart       # 日期格式化、6:00 换日、+08:00 时间序列化
│   ├── diptych_asset_picker.dart # 定制相册选择器（微信风格交互、实况角标与独立开关）
│   ├── file_helper.dart       # 文件与 MIME 类型工具
│   ├── foreground_service_helper.dart # Android 前台保活服务通信通道
│   ├── motion_photo_helper.dart # 实况照片解析器（多厂商动态照片二进制流提取与就地缓存）
│   ├── url_helper.dart        # 相对路径转完整 URL
│   └── wakelock_helper.dart   # CPU WakeLock 原生通道
└── widgets/
    ├── avatar_widget.dart     # 头像组件
    ├── calendar_picker.dart   # 双人状态日历选择弹窗（纸页材质、蓝粉双色状态指示）
    ├── date_header.dart       # 紧凑日期切换栏与日历入口
    ├── day_split_view.dart    # 左右分屏日记展示容器
    ├── frosted_pill_button.dart # 墨蓝实心主操作按钮（保留原组件接口）
    ├── image_gallery.dart     # 全屏手势画廊（原图高清预览、微信手势与实况轻触播放）
    ├── image_preview_chrome.dart # 可隐藏的图片操作层与磨砂玻璃面板
    ├── live_photo_badge.dart  # 实况照片动态徽标与开关角标
    ├── moment_card.dart       # 单条日记卡片（含实况角标与评论树）
    ├── shared_day_view.dart   # 共记模式的单联日视图
    ├── shared_diary_document.dart # A/B 固定配色的共记文字与三列图片渲染
    ├── network_diagnostics_card.dart # 手动网络检测、响应分档、详情及冷却状态
    ├── photo_grid_picker.dart # 九宫格图片选择器（串行上传状态、实况角标切换与拖拽排序）
    └── wallpaper_layer.dart   # 全局/局部壁纸背景渲染层
```

本仓库维护 Flutter 客户端。后端代码、运行时数据、私有配置与 Nginx 部署配置在服务器独立维护，不纳入本仓库。`lib/controllers/` 管理编辑器的串行上传、取消和保活。

`android/` 包含 Kotlin 原生通道、传输前台服务与启动图标资源；`assets/` 只保存 APK 使用的应用图片，目前为应用图标和双方未发布状态贴图，均在 `pubspec.yaml` 中声明。

展示图片统一放在 `pic/`：README 引用的图标和截图放在该目录下，未引用的备选图片、历史截图及原始素材放在 `pic/ignore/`。后者已由 `.gitignore` 忽略，不提交到仓库。以后更新截图时直接替换 `pic/` 中对应的文件；新增图片如需展示，应同步更新 README 引用。

示例截图统一使用“用户A / 用户B”，头像分别取 `assets/not_posted_self.png` 和 `assets/not_posted_partner.png`；日记与话题使用各自的示例壁纸，壁纸原图保存在 `pic/ignore/`。

应用标志使用透明圆角 PNG，Android 同时提供各密度启动图标、自适应图标及单色主题图标，资源位于 `assets/` 与 `android/app/src/main/res/`。

## 后端接口

客户端通过 REST API 访问自托管后端，主要接口如下：

| 用途 | 接口（相对于 API 基础地址） |
|---|---|
| 登录 | `POST /auth/login` |
| 用户 | `POST /users/ensure`、`GET /users/:uid`、`PUT /users/:uid` |
| 日记 | `GET /moments?date_str=…&author_ids=A,B`、`POST /moments`、`PUT /moments/:id` |
| 共记日记 | `GET/POST /shared-moments`、`GET/PUT /shared-moments/:id`、`GET /shared-moments/dates`、`GET /shared-moments/search` |
| 日记详情与评论 | `GET /moments/:id`、`POST /moments/:id/comments`、`DELETE /moments/:id/comments/:commentId` |
| 搜索与日历 | `GET /moments/search`、`GET /moments/calendar/dates` |
| 图片 | `POST /upload/chunk`、`POST /upload/merge`、`POST /upload/abort`、`POST /upload/delete` |
| 话题与帖子 | `GET /topics`、`POST /topics`、`GET /topics/:id`、`POST /topics/:id/posts`、`DELETE /topics/:id/posts/:postId` |
| 通知 | `GET /notifications?user_id=…`（取出后从服务端队列清除） |
| 更新 | `GET /version/latest`、`GET /version/download` |

## 快速开始

### 环境要求

- Flutter 稳定版 ≥ 3.47.0，随附 Dart SDK ≥ 3.13.0 且 < 4.0.0（当前验证环境：Flutter 3.47.7 / Dart 3.13.5；运行 `flutter --version` 确认）
- Android SDK Platform 37.0 与 Build-Tools `37.0.0`；应用及 Android 插件统一使用 `compileSdk = 37`，应用 `targetSdk` 保持 36，最低 Android 版本仍由 Flutter 的 `minSdkVersion` 决定
- Android NDK `28.2.13676358`（构建配置指定）
- JDK 25；应用 Java / Kotlin 编译目标为 25，项目 Gradle Wrapper 使用 Gradle 9.8.1（`bin` 发行包），Android Gradle Plugin 为 9.4.1，Kotlin Gradle Plugin 为 2.4.21。`image_cropper` 与 `open_filex` 的 Java 8 默认目标在根 Gradle 配置中统一为 25
- 当前 Flutter Android 插件仍使用旧 DSL 与 Variant API，`android/gradle.properties` 保留 `android.newDsl=false` 和 `android.builtInKotlin=false` 兼容配置
- `JAVA_HOME` 和 `PATH` 应指向 JDK 25，运行 `flutter doctor -v` 确认 Flutter 实际使用的 Java。项目使用 `jvmToolchain(25)` 明确应用的编译工具链；升级电脑 JDK 不会自动修改第三方插件的编译目标
- JDK 25 下可设置 `GRADLE_OPTS=--enable-native-access=ALL-UNNAMED`，为 Gradle 启动进程的原生库加载提供所需权限，避免 `System::load` 的原生访问提示
- 可用的自托管后端与 Android 真机或模拟器；当前 Android 构建仅包含 `arm64-v8a`，请使用 ARM64 设备或模拟器

Gradle Wrapper 使用 `https://services.gradle.org/distributions/gradle-9.8.1-bin.zip`，默认缓存在用户目录的 `.gradle/wrapper/dists/`。同一账号下，使用相同下载地址且未另设 `GRADLE_USER_HOME` 的项目会复用这份缓存；`bin` 与 `all` 下载地址不同，缓存分别保存。

### 获取代码

```bash
git clone https://github.com/Breeze1733/Diptych.git
cd Diptych
```

### 配置密钥

客户端不再需要 `lib/constants/secrets.dart`。后端需为 A/B 配置各自口令的加盐哈希及会话签名密钥，配置文件只保存在服务器私有目录，由后端独立维护。

登录时通过 `POST /auth/login` 校验输入的口令，成功后保存服务器返回的会话。旧版只有角色的登录态需要重新登录一次；服务器启用鉴权后，旧客户端需要更新。口令不会保存在客户端，也不再打包进 APK。

### 配置后端地址

App 对接自托管 REST API，后端需提供上文列出的接口。在 `lib/constants/` 下创建 `api_config.dart`（该文件已在 `.gitignore` 中排除，不会提交到仓库）：

```dart
class ApiConfig {
  ApiConfig._();

  /// 站点根地址（用于拼接图片等相对路径）
  static const String siteUrl = '<你的站点根地址>';

  /// REST API 基础地址
  static const String apiBaseUrl = '$siteUrl/api';
}
```

> 客户端 API 请求使用 `ApiConfig.apiBaseUrl`，相对图片路径通过 `ApiConfig.siteUrl` 补全。服务端返回的绝对 URL 会保留原地址，因此迁移部署时也需更新后端对应配置。

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

上述工具链已在 Flutter 3.47.7 / Dart 3.13.5 / JDK 25 环境中通过 Release APK 构建验证。

## 隐私与数据

- 🔒 **自托管数据** — 日记、图片与话题数据发送至配置的后端；客户端没有集成第三方账号登录或云数据库 SDK
- 🔑 **服务端鉴权** — 登录口令仅在登录时发往后端，后续私有 API 与照片请求携带 Bearer 会话；服务端校验会话和写操作作者，口令以加盐哈希保存
- 📴 **本地缓存与草稿** — 用户、日记、日历、通知、会话和草稿清单保存在应用私有 SharedPreferences；日记草稿和壁纸设置按账号隔离，草稿图片保存在应用文档目录。有效会话期间可离线浏览已缓存内容，通知已读状态也由本机保存

## 贡献指南

欢迎提交 Issue 与 Pull Request！

- **发现问题**：请先搜索是否已有类似 [Issue](https://github.com/Breeze1733/Diptych/issues)，若无则新建并描述复现步骤与设备信息
- **提交代码**：Fork 仓库 → 基于 `main` 分支新建特性分支 → 提交 PR，按改动需要运行 `flutter analyze` 静态检查或在设备上验证
- **代码风格**：遵循 `analysis_options.yaml` 中的 `flutter_lints` 规则
- **图片维护**：README 图片引用统一使用 `pic/` 路径；未引用的图片移入 `pic/ignore/`，应用运行及 APK 构建资源留在 `assets/` 或 Android 原生资源目录
- **后端备份**：`backend/` 仅保留后端运行源码和版本配置，整个目录不提交到 Git；不保存测试、说明文档、旧副本、安装依赖或临时文件

## License

[MIT](./LICENSE)

Copyright © 2026 Breeze1733
