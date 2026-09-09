import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';
import '../widgets/photo_grid_picker.dart';
import '../widgets/live_photo_badge.dart';
import 'motion_photo_helper.dart';

/// 安全的 AssetPickerProvider，防止当相册为空时出现空指针崩溃导致灰色死锁
class DiptychAssetPickerProvider extends DefaultAssetPickerProvider {
  DiptychAssetPickerProvider({
    super.maxAssets = 999,
    super.requestType = RequestType.image,
    super.pageSize = 80,
  });

  @override
  Future<void> getPaths({
    bool onlyAll = false,
    bool keepPreviousCount = false,
  }) async {
    try {
      await super.getPaths(
        onlyAll: onlyAll,
        keepPreviousCount: keepPreviousCount,
      );
      if (paths.isEmpty) {
        hasAssetsToDisplay = false;
        isAssetsEmpty = true;
        notifyListeners();
      }
    } catch (_) {
      hasAssetsToDisplay = false;
      isAssetsEmpty = true;
      notifyListeners();
    }
  }

  @override
  Future<void> getAssetsFromPath([int? page, AssetPathEntity? path]) async {
    if (currentPath == null && path == null) {
      hasAssetsToDisplay = false;
      isAssetsEmpty = true;
      notifyListeners();
      return;
    }
    await super.getAssetsFromPath(page, path);
  }
}

/// 扩展自 DefaultAssetPickerBuilderDelegate，在底部操作栏嵌入微信同款【实况】开关
class DiptychAssetPickerBuilderDelegate
    extends DefaultAssetPickerBuilderDelegate<DiptychAssetPickerProvider> {
  DiptychAssetPickerBuilderDelegate({
    required super.provider,
    required super.initialPermission,
    super.gridCount = 4,
    super.pickerTheme,
    super.gridThumbnailSize = defaultAssetGridPreviewSize,
    super.previewThumbnailSize,
    super.specialPickerType,
    super.specialItems,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.assetsChangeCallback,
    super.assetsChangeRefreshPredicate,
    super.textDelegate,
    super.themeColor,
    super.locale,
    super.shouldAutoplayPreview = false,
    super.dragToSelect,
    super.enableLivePhoto = true,
  });

  /// 用户选中的实况 Asset ID 集合（支持每张图片独立开关实况）
  final Set<String> liveAssetIds = <String>{};

  /// 通知实况状态更新，驱动底栏和角标刷新
  final ValueNotifier<int> liveNotifier = ValueNotifier<int>(0);

  /// 默认实况倾向（选图时默认静态，用户可主动针对某张图片开启实况）
  bool defaultLive = false;

  @override
  void dispose() {
    liveNotifier.dispose();
    super.dispose();
  }

  @override
  Future<void> selectAsset(
    BuildContext context,
    AssetEntity asset,
    int index,
    bool selected,
  ) async {
    await super.selectAsset(context, asset, index, selected);
    if (!selected) {
      // 刚选中：若默认倾向开启，记录为实况
      if (defaultLive) {
        liveAssetIds.add(asset.id);
      }
    } else {
      // 取消选中：从实况集合中移除
      liveAssetIds.remove(asset.id);
    }
    liveNotifier.value++;
  }

  @override
  Widget selectIndicator(BuildContext context, int index, AssetEntity asset) {
    final selector = super.selectIndicator(context, index, asset);
    return Stack(
      fit: StackFit.expand,
      children: [selector, _buildGridItemLiveBadge(context, asset)],
    );
  }

  /// 在相册网格缩略图左下角显示的实况角标：只要是实况照片，在缩略图清晰标示「实况」

  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    final revert = effectiveShouldRevertGrid(context);
    final List<AssetEntity> current;
    final int effectiveIndex;
    if (index == null) {
      current = revert
          ? provider.selectedAssets.reversed.toList(growable: false)
          : provider.selectedAssets;
      effectiveIndex = current.indexOf(currentAsset);
    } else {
      current = provider.currentAssets;
      effectiveIndex = revert ? current.length - index - 1 : index;
    }

    if (current.isEmpty) return;

    final result = await Navigator.of(context).push<List<AssetEntity>>(
      MaterialPageRoute(
        builder: (_) => _DiptychAssetViewerScreen(
          previewAssets: current,
          initialIndex: effectiveIndex >= 0 ? effectiveIndex : 0,
          provider: provider,
          liveAssetIds: liveAssetIds,
          liveNotifier: liveNotifier,
          textDelegate: textDelegate,
          themeColor: themeColor,
        ),
      ),
    );

    if (result != null && context.mounted) {
      Navigator.maybeOf(context)?.maybePop(result);
    }
  }

  Widget _buildGridItemLiveBadge(BuildContext context, AssetEntity asset) {
    return _AssetPickerLiveBadge(asset: asset, liveAssetIds: liveAssetIds, liveNotifier: liveNotifier);
  }

  @override
  Widget emptyIndicator(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            const Text(
              '相册中未读取到照片',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '若手机中有照片，请检查：\n1. 系统设置中是否已授予【照片和视频】全部权限\n2. 若刚修改权限或代码，请重新安装运行应用（热重载无法更新系统清单权限）',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: PhotoManager.openSetting,
              child: const Text('去系统设置'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget confirmButton(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final bool isSelectedNotEmpty = provider.isSelectedNotEmpty;
        final bool shouldAllowConfirm =
            isSelectedNotEmpty || provider.previousSelectedAssets.isNotEmpty;
        return MaterialButton(
          minWidth: shouldAllowConfirm ? 48 : 20,
          height: appBarItemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: theme.colorScheme.secondary,
          disabledColor: theme.splashColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          onPressed: shouldAllowConfirm
              ? () {
                  Navigator.maybeOf(context)?.maybePop(provider.selectedAssets);
                }
              : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          child: Text(
            isSelectedNotEmpty
                ? '${textDelegate.confirm} (${provider.selectedAssets.length})'
                : textDelegate.confirm,
            style: TextStyle(
              color: shouldAllowConfirm
                  ? theme.textTheme.bodyLarge?.color
                  : theme.textTheme.bodySmall?.color,
              fontSize: 17,
              fontWeight: FontWeight.normal,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget bottomActionBar(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final appBarColor = theme.bottomAppBarTheme.color ?? theme.canvasColor;
    final children = <Widget>[
      if (isPermissionLimited) accessLimitedBottomTip(context),
      if (hasBottomActions)
        Container(
          height: bottomActionBarHeight + bottomPadding,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ).copyWith(bottom: bottomPadding),
          color: appBarColor.withValues(
            alpha: appBarColor.a * (isAppleOS(context) ? .9 : 1),
          ),
          child: Row(
            children: <Widget>[
              if (isPreviewEnabled) previewButton(context),
              const Spacer(),
              // 微信同款「实况」配置与开关按钮（仅当选中的图片中包含实况照片时展示，没有实况的不做选择）
              ListenableBuilder(
                listenable: Listenable.merge([provider, liveNotifier]),
                builder: (context, _) {
                  final selectedAssets = provider.selectedAssets;
                  final liveAssets = selectedAssets
                      .where((a) =>
                          MotionPhotoHelper.isLiveOrCachedMotion(a) ||
                          liveAssetIds.contains(a.id))
                      .toList();

                  // 若选中的图片中没有任何实况照片，不展示实况按钮
                  if (liveAssets.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final liveCount = liveAssets
                      .where((a) => liveAssetIds.contains(a.id))
                      .length;

                  final String btnText;
                  final bool isHighlight;

                  if (liveAssets.length == 1) {
                    final isLive = liveAssetIds.contains(liveAssets.first.id);
                    btnText = '实况';
                    isHighlight = isLive;
                  } else {
                    if (liveCount == 0) {
                      btnText = '实况关 (${liveAssets.length})';
                      isHighlight = false;
                    } else if (liveCount == liveAssets.length) {
                      btnText = '实况全开 (${liveAssets.length})';
                      isHighlight = true;
                    } else {
                      btnText = '实况 ($liveCount/${liveAssets.length})';
                      isHighlight = true;
                    }
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (liveAssets.length == 1) {
                        final asset = liveAssets.first;
                        if (liveAssetIds.contains(asset.id)) {
                          liveAssetIds.remove(asset.id);
                        } else {
                          liveAssetIds.add(asset.id);
                        }
                        liveNotifier.value++;
                      } else {
                        _showMultiLiveSettingsSheet(context, liveAssets);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isHighlight
                            ? const Color(0xFF07C160).withAlpha(230)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isHighlight ? Colors.white70 : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: CustomPaint(
                        foregroundPainter: isHighlight
                            ? null
                            : const DiagonalSlashPainter(
                                color: Colors.white,
                                strokeWidth: 1.6,
                              ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isHighlight
                                  ? Icons.motion_photos_on
                                  : Icons.motion_photos_off_outlined,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              btnText,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: isHighlight
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              if (isPreviewEnabled || !isSingleAssetMode)
                confirmButton(context),
            ],
          ),
        ),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// 当选了多张图片时，弹出底部抽屉分别设置每张实况图片的实况开关（仅展示实况图，非实况图不做选择）
  void _showMultiLiveSettingsSheet(
    BuildContext context,
    List<AssetEntity> liveAssets,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF232323),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final liveCount = liveAssets
                .where((a) => liveAssetIds.contains(a.id))
                .length;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          '设置实况照片',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '($liveCount/${liveAssets.length} 张开启)',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              for (final a in liveAssets) {
                                liveAssetIds.add(a.id);
                              }
                            });
                            liveNotifier.value++;
                          },
                          child: const Text(
                            '全开',
                            style: TextStyle(color: Color(0xFF07C160)),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              for (final a in liveAssets) {
                                liveAssetIds.remove(a.id);
                              }
                            });
                            liveNotifier.value++;
                          },
                          child: const Text(
                            '全关',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: liveAssets.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final asset = liveAssets[index];
                          final isLive = liveAssetIds.contains(asset.id);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image(
                                    image: AssetEntityImageProvider(
                                      asset,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize.square(
                                        120,
                                      ),
                                    ),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '照片 ${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isLive ? '作为实况照片上传' : '仅上传普通静态照片',
                                        style: TextStyle(
                                          color: isLive
                                              ? const Color(0xFF07C160)
                                              : Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setSheetState(() {
                                      if (isLive) {
                                        liveAssetIds.remove(asset.id);
                                      } else {
                                        liveAssetIds.add(asset.id);
                                      }
                                    });
                                    liveNotifier.value++;
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLive
                                          ? const Color(0xFF07C160).withAlpha(230)
                                          : Colors.black54,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isLive
                                            ? Colors.white70
                                            : Colors.white24,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: CustomPaint(
                                      foregroundPainter: isLive
                                          ? null
                                          : const DiagonalSlashPainter(
                                              color: Colors.white,
                                              strokeWidth: 1.6,
                                            ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isLive
                                                ? Icons.motion_photos_on
                                                : Icons.motion_photos_off_outlined,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '实况',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: isLive
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF07C160),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 微信风格相册选择器入口封装
class DiptychAssetPicker {
  DiptychAssetPicker._();

  static const PermissionRequestOption _permissionOption =
      PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      );

  static Future<List<PhotoEntry>?> pickPhotos(
    BuildContext context, {
    int maxAssets = 999,
  }) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: _permissionOption,
    );
    if (!context.mounted) return null;

    if (!ps.isAuth && ps != PermissionState.limited) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要相册权限'),
          content: const Text('未获得相册读取权限，请在系统设置中允许访问相册后再试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                PhotoManager.openSetting();
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      return null;
    }

    final provider = DiptychAssetPickerProvider(
      maxAssets: maxAssets,
      requestType: RequestType.image,
    );

    final delegate = DiptychAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: ps,
      themeColor: const Color(0xFF07C160),
      textDelegate: const AssetPickerTextDelegate(),
      enableLivePhoto: true,
      gridThumbnailSize: const ThumbnailSize.square(400),
      limitedPermissionOverlayPredicate: (state) => false,
    );

    if (!context.mounted) return null;

    List<AssetEntity>? assets;
    try {
      assets =
          await AssetPicker.pickAssetsWithDelegate<
            AssetEntity,
            AssetPathEntity,
            DiptychAssetPickerProvider,
            DiptychAssetPickerBuilderDelegate
          >(
            context,
            delegate: delegate,
            permissionRequestOption: _permissionOption,
          );
    } catch (e, stack) {
      debugPrint('AssetPicker.pickAssetsWithDelegate 异常: $e\n$stack');
      return null;
    }

    if (assets == null || assets.isEmpty) {
      return null;
    }

    final entries = <PhotoEntry>[];
    for (final asset in assets) {
      final file = await asset.originFile ?? await asset.file;
      if (file != null) {
        final isMotion = await MotionPhotoHelper.isMotionPhoto(file);
        final isLiveSelected = delegate.liveAssetIds.contains(asset.id);
        entries.add(
          PhotoEntry.file(
            file,
            isMotion: isMotion,
            uploadLive: isMotion && isLiveSelected,
          ),
        );
      }
    }

    return entries;
  }
}

/// 相册缩略图网格中的实况角标：如果是实况图，显示实况角标（未选择带斜杠，选择无斜杠），非实况图不显示
class _AssetPickerLiveBadge extends StatefulWidget {
  final AssetEntity asset;
  final Set<String> liveAssetIds;
  final ValueNotifier<int> liveNotifier;

  const _AssetPickerLiveBadge({
    required this.asset,
    required this.liveAssetIds,
    required this.liveNotifier,
  });

  @override
  State<_AssetPickerLiveBadge> createState() => _AssetPickerLiveBadgeState();
}

class _AssetPickerLiveBadgeState extends State<_AssetPickerLiveBadge> {
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    _checkLive();
  }

  @override
  void didUpdateWidget(_AssetPickerLiveBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _checkLive();
    }
  }

  Future<void> _checkLive() async {
    if (widget.asset.isLivePhoto) {
      if (mounted) setState(() => _isLive = true);
      return;
    }
    final isLive = await MotionPhotoHelper.isMotionPhotoAsset(widget.asset);
    if (mounted && isLive) {
      setState(() => _isLive = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不能选择实况的普通静态图片不显示任何角标
    if (!_isLive) return const SizedBox.shrink();

    return Positioned(
      left: 4,
      bottom: 4,
      child: ListenableBuilder(
        listenable: widget.liveNotifier,
        builder: (context, _) {
          final isSelected = widget.liveAssetIds.contains(widget.asset.id);
          return LivePhotoBadge(
            isLiveSelected: isSelected,
            onTap: () {
              if (isSelected) {
                widget.liveAssetIds.remove(widget.asset.id);
              } else {
                widget.liveAssetIds.add(widget.asset.id);
              }
              widget.liveNotifier.value++;
            },
          );
        },
      ),
    );
  }
}

/// 相册选图大图预览页面（微信同款：有实况的显示实况开关，勾选播放一遍，取消不播放；无实况的不显示做选择）
class _DiptychAssetViewerScreen extends StatefulWidget {
  final List<AssetEntity> previewAssets;
  final int initialIndex;
  final DiptychAssetPickerProvider provider;
  final Set<String> liveAssetIds;
  final ValueNotifier<int> liveNotifier;
  final AssetPickerTextDelegate textDelegate;
  final Color? themeColor;

  const _DiptychAssetViewerScreen({
    required this.previewAssets,
    required this.initialIndex,
    required this.provider,
    required this.liveAssetIds,
    required this.liveNotifier,
    required this.textDelegate,
    this.themeColor,
  });

  @override
  State<_DiptychAssetViewerScreen> createState() =>
      _DiptychAssetViewerScreenState();
}

class _DiptychAssetViewerScreenState
    extends State<_DiptychAssetViewerScreen> {
  late int _currentIndex;
  late PageController _pageController;

  VideoPlayerController? _videoController;
  bool _isMotionPhoto = false;
  bool _isPlaying = false;
  int _checkingIndex = -1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _checkMotionPhotoForIndex(_currentIndex);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkMotionPhotoForIndex(int index) async {
    _checkingIndex = index;

    final oldController = _videoController;
    _videoController = null;
    if (mounted) {
      setState(() {
        _isMotionPhoto = false;
        _isPlaying = false;
      });
    }
    await oldController?.dispose();

    if (index < 0 || index >= widget.previewAssets.length) return;
    final asset = widget.previewAssets[index];

    bool isMotion = asset.isLivePhoto;
    if (!isMotion) {
      isMotion = await MotionPhotoHelper.isMotionPhotoAsset(asset);
    }
    if (!isMotion || !mounted || _checkingIndex != index) return;

    setState(() => _isMotionPhoto = true);

    final file = await asset.originFile ?? await asset.file;
    if (file == null || !mounted || _checkingIndex != index) return;

    final videoFile = await MotionPhotoHelper.getOrExtractMotionVideo(file);
    if (videoFile == null || !mounted || _checkingIndex != index) return;

    final controller = VideoPlayerController.file(videoFile);
    try {
      await controller.initialize();
      if (!mounted || _checkingIndex != index) {
        await controller.dispose();
        return;
      }

      controller.addListener(() {
        if (!mounted) return;
        if (controller.value.isInitialized) {
          final isEnded =
              controller.value.position >= controller.value.duration;
          if (isEnded && _isPlaying) {
            setState(() => _isPlaying = false);
            controller.pause();
            controller.seekTo(Duration.zero);
          }
        }
      });

      setState(() {
        _videoController = controller;
        _isMotionPhoto = true;
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  void _onPageChanged(int index) {
    if (_isPlaying && _videoController != null) {
      _videoController!.pause();
      _videoController!.seekTo(Duration.zero);
      _isPlaying = false;
    }
    setState(() => _currentIndex = index);
    _checkMotionPhotoForIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final currentAsset = widget.previewAssets[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 照片手势缩放与翻页
          PhotoViewGallery.builder(
            itemCount: widget.previewAssets.length,
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: AssetEntityImageProvider(
                widget.previewAssets[index],
                isOriginal: true,
              ),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4.0,
            ),
            loadingBuilder: (context, event) => Center(
              child: Image(
                image: AssetEntityImageProvider(
                  widget.previewAssets[
                      _currentIndex.clamp(0, widget.previewAssets.length - 1)],
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(400),
                ),
                fit: BoxFit.contain,
              ),
            ),
            pageController: _pageController,
            onPageChanged: _onPageChanged,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            gaplessPlayback: true,
          ),

          // 2. 视频贴合层：播放中显示
          if (_isMotionPhoto &&
              _isPlaying &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              ),
            ),

          // 3. 顶部操作栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 8,
                right: 16,
                bottom: 8,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentIndex + 1} / ${widget.previewAssets.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: widget.provider,
                    builder: (context, _) {
                      final isSelected = widget.provider.selectedAssets.contains(currentAsset);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.provider.selectAsset(currentAsset);
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? const Color(0xFF07C160) : Colors.black38,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 4. 底部微信同款「实况」开关与「完成」确定按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.paddingOf(context).bottom + 12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  // 实况开关（仅当当前图片为实况时显示，非实况图绝不显示做选择）
                  if (_isMotionPhoto)
                    ListenableBuilder(
                      listenable: widget.liveNotifier,
                      builder: (context, _) {
                        final isLiveSelected = widget.liveAssetIds.contains(currentAsset.id);

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            final newLive = !isLiveSelected;
                            if (newLive) {
                              widget.liveAssetIds.add(currentAsset.id);
                            } else {
                              widget.liveAssetIds.remove(currentAsset.id);
                            }
                            widget.liveNotifier.value++;

                            if (newLive) {
                              // 勾选实况：播放一遍实况
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized) {
                                await _videoController!.seekTo(Duration.zero);
                                await _videoController!.play();
                                if (mounted) setState(() => _isPlaying = true);
                              }
                            } else {
                              // 取消实况：不播放
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized) {
                                await _videoController!.pause();
                                await _videoController!.seekTo(Duration.zero);
                              }
                              if (mounted) setState(() => _isPlaying = false);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isLiveSelected
                                  ? const Color(0xFF07C160).withAlpha(230)
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isLiveSelected ? Colors.white70 : Colors.white30,
                                width: 0.8,
                              ),
                            ),
                            child: CustomPaint(
                              foregroundPainter: isLiveSelected
                                  ? null
                                  : const DiagonalSlashPainter(color: Colors.white, strokeWidth: 1.6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isLiveSelected
                                        ? Icons.motion_photos_on
                                        : Icons.motion_photos_off_outlined,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '实况',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  // 完成按钮
                  ListenableBuilder(
                    listenable: widget.provider,
                    builder: (context, _) {
                      final count = widget.provider.selectedAssets.length;
                      final label = count > 0 ? '完成 ($count)' : '完成';
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF07C160),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          if (widget.provider.selectedAssets.isEmpty) {
                            widget.provider.selectAsset(currentAsset);
                          }
                          Navigator.pop(context, widget.provider.selectedAssets);
                        },
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
