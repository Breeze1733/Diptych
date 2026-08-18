import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../models/app_user.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
import '../widgets/date_header.dart';
import '../widgets/day_split_view.dart';
import '../widgets/wallpaper_layer.dart';

/// 壁纸透明度预览页：
/// - 背景：该类型壁纸 + 当前透明度
/// - 前景：与日记页一模一样的布局（DateHeader + 分屏卡片），仅文字为预设示例
/// - 滑条实时改内存透明度；点「应用」才写本地 + 推云端
class WallpaperPreviewScreen extends ConsumerStatefulWidget {
  final WallpaperType type;
  final String url;
  final double initialOpacity;

  const WallpaperPreviewScreen({
    super.key,
    required this.type,
    required this.url,
    required this.initialOpacity,
  });

  @override
  ConsumerState<WallpaperPreviewScreen> createState() =>
      _WallpaperPreviewScreenState();
}

class _WallpaperPreviewScreenState extends ConsumerState<WallpaperPreviewScreen> {
  late double _opacity;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _opacity = widget.initialOpacity;
  }

  /// 确定应用：写本地 + 推云端 + 更新整对象缓存
  Future<void> _apply() async {
    if (_applying) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _applying = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final settings = ref.read(wallpaperSettingsProvider);
      final isDiary = widget.type == WallpaperType.diary;

      // 推云端
      if (isDiary) {
        await apiService.updateUser(user.uid, wallpaperDiaryOpacity: _opacity);
      } else {
        await apiService.updateUser(user.uid, wallpaperTopicOpacity: _opacity);
      }

      // 写本地（provider + 本地 key + 整对象缓存）
      final newSettings = settings.copyWith(
        diaryOpacity: isDiary ? _opacity : null,
        topicOpacity: isDiary ? null : _opacity,
      );
      ref.read(wallpaperSettingsProvider.notifier).setSettings(newSettings);
      await saveWallpaperSettings(newSettings);
      await CacheService.saveUser(_withWallpaper(user, newSettings));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已应用'), backgroundColor: AppTheme.primaryColor),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('应用失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// 把壁纸设置合并进 AppUser（用于本地整对象缓存）
  AppUser _withWallpaper(AppUser user, WallpaperSettings s) {
    return user.copyWith(
      wallpaperDiaryUrl: s.diaryUrl,
      wallpaperTopicUrl: s.topicUrl,
      wallpaperDiaryOpacity: s.diaryOpacity,
      wallpaperTopicOpacity: s.topicOpacity,
    );
  }

  /// 与日记页一致的示例数据
  (Moment, Moment) _sampleMoments() {
    final now = DateTime.now();
    final dateStr = DateHelper.toDateStr(now);
    final self = Moment(
      id: 'preview_self',
      dateStr: dateStr,
      authorId: 'A',
      feeling: '示例感受文字，用于预览壁纸与文字的对比效果。\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位',
      mood: 8,
      comments: [
        Comment(
          id: 'preview_c1',
          authorId: 'B',
          content: '示例评论：壁纸下文字清晰可读',
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final partner = Moment(
      id: 'preview_partner',
      dateStr: dateStr,
      authorId: 'B',
      feeling: '对方的示例日记内容，同样用来预览壁纸效果。\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位\n换行占位',
      mood: 6,
      comments: [
        Comment(
          id: 'preview_c2',
          authorId: 'A',
          content: '示例回复：双方都能看到壁纸背景',
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    return (self, partner);
  }

  /// 日记壁纸预览：与日记页一致的示例布局，昵称/头像固定为占位，不显示真实用户
  Widget _buildDiaryPreview(Moment selfMoment, Moment partnerMoment) {
    return Column(
      children: [
        // 与日记页一致的日期顶栏（示例日期）
        DateHeader(
          dateText: DateHelper.toChineseDate(DateTime.now()),
          onCalendarTap: () {}, // 预览页日历不响应
        ),
        const Divider(height: 1, thickness: 1, color: AppTheme.dividerColor),
        // 与日记页一致的分屏卡片，昵称固定「用户A/用户B」，头像留空
        DaySplitView(
          myMoment: selfMoment,
          partnerMoment: partnerMoment,
          myNickname: '用户A',
          partnerNickname: '用户B',
        ),
      ],
    );
  }

  /// 话题壁纸预览：与话题列表页一致的示例布局
  Widget _buildTopicPreview() {
    const samples = [
      ('示例话题文字', '用户A'),
      ('周末去哪儿玩', '用户B'),
      ('推荐一部值得看的电影', '用户A'),
    ];
    return ListView.separated(
      itemCount: samples.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final (title, author) = samples[index];
        return ListTile(
          isThreeLine: true,
          title: SelectableText(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('由 $author 创建', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 2),
              Text('最新更新：示例时间', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final (selfMoment, partnerMoment) = _sampleMoments();
    final isDiary = widget.type == WallpaperType.diary;

    final body = isDiary
        ? _buildDiaryPreview(selfMoment, partnerMoment)
        : _buildTopicPreview();

    // 壁纸垫在整个 Scaffold 后面，Scaffold 保持正常布局，杜绝重叠/空档
    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(url: widget.url, opacity: _opacity),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(isDiary ? '日记壁纸预览' : '话题壁纸预览'),
            actions: [
              TextButton(
                onPressed: _applying ? null : _apply,
                child: _applying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('应用', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          body: body,
          floatingActionButton: isDiary
              ? null
              : FloatingActionButton(
                  onPressed: () {}, // 预览页不响应
                  child: const Icon(Icons.add),
                ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('不透明度', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          onChanged: (v) => setState(() => _opacity = v),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(_opacity * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '拖动滑条实时预览，点右上角「应用」保存到云端',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
