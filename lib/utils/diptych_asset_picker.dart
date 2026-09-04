import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../widgets/photo_grid_picker.dart';
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
      await super.getPaths(onlyAll: onlyAll, keepPreviousCount: keepPreviousCount);
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
      children: [
        selector,
        _buildGridItemLiveBadge(context, asset),
      ],
    );
  }

  /// 在相册网格缩略图左下角显示的单张实况切换角标
  Widget _buildGridItemLiveBadge(BuildContext context, AssetEntity asset) {
    return ListenableBuilder(
      listenable: Listenable.merge([provider, liveNotifier]),
      builder: (context, _) {
        final isSelected = provider.selectedAssets.contains(asset);
        if (!isSelected) {
          return const SizedBox.shrink();
        }

        final isLive = liveAssetIds.contains(asset.id);

        return Positioned(
          left: 4,
          bottom: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (isLive) {
                liveAssetIds.remove(asset.id);
              } else {
                liveAssetIds.add(asset.id);
              }
              liveNotifier.value++;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
              decoration: BoxDecoration(
                color: isLive
                    ? const Color(0xFF07C160)
                    : Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isLive ? Colors.white70 : Colors.white24,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLive ? Icons.motion_photos_on : Icons.motion_photos_off,
                    size: 11,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isLive ? '实况' : '实况关',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(
            bottom: bottomPadding,
          ),
          color: appBarColor.withValues(
            alpha: appBarColor.a * (isAppleOS(context) ? .9 : 1),
          ),
          child: Row(
            children: <Widget>[
              if (isPreviewEnabled) previewButton(context),
              const Spacer(),
              // 微信同款「实况」配置与开关按钮
              ListenableBuilder(
                listenable: Listenable.merge([provider, liveNotifier]),
                builder: (context, _) {
                  final selectedAssets = provider.selectedAssets;
                  final selectedCount = selectedAssets.length;
                  final liveCount = selectedAssets
                      .where((a) => liveAssetIds.contains(a.id))
                      .length;

                  final String btnText;
                  final bool isHighlight;
                  final IconData btnIcon;

                  if (selectedCount == 0) {
                    btnText = defaultLive ? '实况开' : '实况关';
                    isHighlight = defaultLive;
                    btnIcon = defaultLive
                        ? Icons.motion_photos_on
                        : Icons.motion_photos_off;
                  } else if (selectedCount == 1) {
                    final singleLive =
                        liveAssetIds.contains(selectedAssets.first.id);
                    btnText = singleLive ? '实况' : '实况关';
                    isHighlight = singleLive;
                    btnIcon = singleLive
                        ? Icons.motion_photos_on
                        : Icons.motion_photos_off;
                  } else {
                    if (liveCount == 0) {
                      btnText = '实况关 ($selectedCount)';
                      isHighlight = false;
                      btnIcon = Icons.motion_photos_off;
                    } else if (liveCount == selectedCount) {
                      btnText = '实况全开 ($selectedCount)';
                      isHighlight = true;
                      btnIcon = Icons.motion_photos_on;
                    } else {
                      btnText = '实况 ($liveCount/$selectedCount)';
                      isHighlight = true;
                      btnIcon = Icons.motion_photos_on;
                    }
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (selectedCount == 0) {
                        defaultLive = !defaultLive;
                        liveNotifier.value++;
                      } else if (selectedCount == 1) {
                        final asset = selectedAssets.first;
                        if (liveAssetIds.contains(asset.id)) {
                          liveAssetIds.remove(asset.id);
                        } else {
                          liveAssetIds.add(asset.id);
                        }
                        liveNotifier.value++;
                      } else {
                        _showMultiLiveSettingsSheet(context);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isHighlight
                            ? const Color(0xFF07C160)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isHighlight ? Colors.white70 : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            btnIcon,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// 当选了多张图片时，弹出底部抽屉分别设置每张图片的实况开关
  void _showMultiLiveSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF232323),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final selectedAssets = provider.selectedAssets;
            final liveCount = selectedAssets
                .where((a) => liveAssetIds.contains(a.id))
                .length;

            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          '($liveCount/${selectedAssets.length} 张开启)',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              for (final a in selectedAssets) {
                                liveAssetIds.add(a.id);
                              }
                            });
                            liveNotifier.value++;
                          },
                          child: const Text('全开',
                              style: TextStyle(color: Color(0xFF07C160))),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              for (final a in selectedAssets) {
                                liveAssetIds.remove(a.id);
                              }
                            });
                            liveNotifier.value++;
                          },
                          child: const Text('全关',
                              style: TextStyle(color: Colors.white70)),
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
                        itemCount: selectedAssets.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final asset = selectedAssets[index];
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
                                      thumbnailSize:
                                          const ThumbnailSize.square(120),
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
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isLive
                                          ? const Color(0xFF07C160)
                                          : Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isLive
                                            ? Colors.white70
                                            : Colors.white24,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isLive
                                              ? Icons.motion_photos_on
                                              : Icons.motion_photos_off,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isLive ? '实况' : '实况关',
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
                        child: const Text('确定',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
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
      limitedPermissionOverlayPredicate: (state) => false,
    );

    if (!context.mounted) return null;

    List<AssetEntity>? assets;
    try {
      assets = await AssetPicker.pickAssetsWithDelegate<
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
        entries.add(PhotoEntry.file(
          file,
          isMotion: isMotion,
          uploadLive: isMotion && isLiveSelected,
        ));
      }
    }

    return entries;
  }
}
