import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/selected_date_provider.dart';
import '../utils/date_helper.dart';
import '../utils/diary_search.dart';
import '../widgets/avatar_widget.dart';
import 'diary_reading_screen.dart';
import 'shared_diary_reading_screen.dart';

Future<({T? value, Object? error})> _settleOptional<T>(
  Future<T>? future,
) async {
  if (future == null) return (value: null, error: null);
  try {
    return (value: await future, error: null);
  } catch (error) {
    return (value: null, error: error);
  }
}

/// 日记搜索页面。
class DiarySearchScreen extends ConsumerStatefulWidget {
  const DiarySearchScreen({super.key});

  @override
  ConsumerState<DiarySearchScreen> createState() => _DiarySearchScreenState();
}

class _DiarySearchScreenState extends ConsumerState<DiarySearchScreen> {
  static const _pageSize = 10;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  int _searchGeneration = 0;
  String _keyword = '';
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _legacyHasMore = false;
  bool _sharedHasMore = false;
  String? _legacyNextCursor;
  String? _sharedNextCursor;
  String? _errorMessage;
  String? _partialErrorMessage;
  List<DiarySearchHit> _allHits = [];
  List<DiarySearchHit> _hits = [];
  int _visibleCount = 0;

  bool get _hasMore =>
      _legacyHasMore || _sharedHasMore || _visibleCount < _allHits.length;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    // 退出搜索界面彻底销毁缓存与游标
    _hits.clear();
    _allHits.clear();
    _legacyNextCursor = null;
    _sharedNextCursor = null;
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 120;
    if (_scrollController.position.pixels >= threshold) {
      if (_hasMore && !_isLoadingMore && !_isSearching) {
        _performSearch(_keyword, isLoadMore: true);
      }
    }
  }

  void _onQueryChanged(String val) {
    _debounceTimer?.cancel();
    // 输入一变就使在途请求失效，防止旧响应在防抖等待期间写回。
    final generation = ++_searchGeneration;
    if (val.trim().isEmpty) {
      _performSearch('', generation: generation);
      return;
    }
    setState(() {
      _isSearching = true;
      _isLoadingMore = false;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(val, generation: generation);
    });
  }

  Future<void> _performSearch(
    String query, {
    bool isLoadMore = false,
    int? generation,
  }) async {
    if (!mounted) return;
    if (!isLoadMore) _debounceTimer?.cancel();
    final requestGeneration = isLoadMore
        ? _searchGeneration
        : generation ?? ++_searchGeneration;
    if (requestGeneration != _searchGeneration) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _keyword = '';
        _hits.clear();
        _allHits.clear();
        _visibleCount = 0;
        _isSearching = false;
        _isLoadingMore = false;
        _legacyHasMore = false;
        _sharedHasMore = false;
        _legacyNextCursor = null;
        _sharedNextCursor = null;
        _errorMessage = null;
        _partialErrorMessage = null;
      });
      return;
    }

    if (!isLoadMore) {
      setState(() {
        _keyword = trimmed;
        _hits.clear();
        _allHits.clear();
        _visibleCount = 0;
        _isSearching = true;
        _isLoadingMore = false;
        _legacyHasMore = false;
        _sharedHasMore = false;
        _legacyNextCursor = null;
        _sharedNextCursor = null;
        _errorMessage = null;
        _partialErrorMessage = null;
      });
    } else {
      if (_isLoadingMore || _isSearching || !_hasMore || trimmed != _keyword) {
        return;
      }
      setState(() => _isLoadingMore = true);
    }

    try {
      final currentUser = ref.read(currentUserProvider);
      final partner = ref.read(partnerUserProvider);
      final authorIds = <String>[
        if (currentUser != null) currentUser.uid,
        if (partner != null) partner.uid,
      ];

      final apiService = ref.read(apiServiceProvider);
      // 两个后端资源维持独立游标；只为仍有下一页的资源继续请求。
      final legacyFuture = !isLoadMore || _legacyHasMore
          ? apiService.searchMoments(
              trimmed,
              authorIds,
              limit: _pageSize,
              cursor: isLoadMore ? _legacyNextCursor : null,
            )
          : null;
      final sharedFuture = !isLoadMore || _sharedHasMore
          ? apiService.searchSharedMoments(
              trimmed,
              limit: _pageSize,
              cursor: isLoadMore ? _sharedNextCursor : null,
            )
          : null;

      final (legacySettled, sharedSettled) = await (
        _settleOptional(legacyFuture),
        _settleOptional(sharedFuture),
      ).wait;

      if (!mounted || requestGeneration != _searchGeneration) return;

      final requestedCount = [
        legacyFuture,
        sharedFuture,
      ].where((future) => future != null).length;
      final failedCount = [
        legacySettled.error,
        sharedSettled.error,
      ].where((error) => error != null).length;
      if (requestedCount > 0 &&
          failedCount == requestedCount &&
          (!isLoadMore || _allHits.isEmpty)) {
        throw StateError('所有搜索源都不可用');
      }

      final legacyResult = legacySettled.value;
      final sharedResult = sharedSettled.value;

      final newHits = mergeDiarySearchHits(
        legacyResult == null
            ? const <DiarySearchHit>[]
            : buildLegacyMomentSearchHits(legacyResult.items, trimmed),
        sharedResult == null
            ? const <DiarySearchHit>[]
            : buildSharedMomentSearchHits(sharedResult.items, trimmed),
      );

      setState(() {
        _allHits = mergeDiarySearchHits(
          isLoadMore ? _allHits : const <DiarySearchHit>[],
          newHits,
        );
        if (legacyResult != null) {
          _legacyHasMore = legacyResult.hasMore;
          _legacyNextCursor = legacyResult.nextCursor;
        }
        if (sharedResult != null) {
          _sharedHasMore = sharedResult.hasMore;
          _sharedNextCursor = sharedResult.nextCursor;
        }
        if (legacySettled.error != null) {
          _legacyHasMore = false;
          _legacyNextCursor = null;
        }
        if (sharedSettled.error != null) {
          _sharedHasMore = false;
          _sharedNextCursor = null;
        }
        _visibleCount = (isLoadMore ? _visibleCount + _pageSize : _pageSize)
            .clamp(0, _allHits.length);
        _hits = _allHits.take(_visibleCount).toList(growable: false);
        _isSearching = false;
        _isLoadingMore = false;
        _errorMessage = null;
        _partialErrorMessage = failedCount == 0
            ? null
            : legacySettled.error != null
            ? '旧双联搜索暂时不可用，以下结果可能不完整'
            : '共记搜索暂时不可用，以下结果可能不完整';
      });
    } catch (e) {
      if (!mounted || requestGeneration != _searchGeneration) return;
      setState(() {
        _isSearching = false;
        _isLoadingMore = false;
        _errorMessage = '搜索失败，请检查网络';
      });
    }
  }

  Future<void> _openHit(DiarySearchHit hit) async {
    try {
      final targetDate = DateHelper.parseDateStr(hit.dateStr);
      ref.read(selectedDateProvider.notifier).setDate(targetDate);
      final route = switch (hit.kind) {
        DiarySearchHitKind.legacy when hit.legacyMoment != null =>
          MaterialPageRoute<void>(
            builder: (_) =>
                DiaryReadingScreen(initialMoment: hit.legacyMoment!),
          ),
        DiarySearchHitKind.shared when hit.sharedMoment != null =>
          MaterialPageRoute<void>(
            builder: (_) =>
                SharedDiaryReadingScreen(initialMoment: hit.sharedMoment!),
          ),
        _ => null,
      };
      if (route != null && mounted) await Navigator.push(context, route);
    } catch (e) {
      debugPrint('跳转日期失败: $e');
    }
  }

  static const int _snippetRadius = 10;

  /// 构建上下文片段（严格遵循：前10字 + 关键词标粗 + 后10字，不足空着绝不填充）
  Widget _buildSnippet(String content, String keyword) {
    if (keyword.isEmpty) {
      return Text(content, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final lowerContent = content.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final matchIndex = lowerContent.indexOf(lowerKeyword);

    if (matchIndex == -1) {
      return Text(content, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    // 前置文字：最多 _snippetRadius 字，不足实际是多少就多少，绝不填充补空
    final hasMoreBefore = matchIndex > _snippetRadius;
    final start = hasMoreBefore ? matchIndex - _snippetRadius : 0;
    final prefixRaw = content
        .substring(start, matchIndex)
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    final prefix = (hasMoreBefore ? '...' : '') + prefixRaw;

    // 关键词原字形
    final keywordText = content.substring(
      matchIndex,
      matchIndex + keyword.length,
    );

    // 后置文字：最多 _snippetRadius 字，不足实际是多少就多少，绝不填充补空
    final endOfKeyword = matchIndex + keyword.length;
    final remaining = content.length - endOfKeyword;
    final hasMoreAfter = remaining > _snippetRadius;
    final end = hasMoreAfter ? endOfKeyword + _snippetRadius : content.length;
    final suffixRaw = content
        .substring(endOfKeyword, end)
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    final suffix = suffixRaw + (hasMoreAfter ? '...' : '');

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          TextSpan(
            text: keywordText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              backgroundColor: AppTheme.accentSurface,
            ),
          ),
          TextSpan(
            text: suffix,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _getNickname(String authorId) {
    final currentUser = ref.read(currentUserProvider);
    final partner = ref.read(partnerUserProvider);
    if (currentUser != null && currentUser.uid == authorId) {
      return currentUser.nickname.isNotEmpty ? currentUser.nickname : '我';
    }
    if (partner != null && partner.uid == authorId) {
      return partner.nickname.isNotEmpty ? partner.nickname : '对方';
    }
    return '用户$authorId';
  }

  String _getAvatarUrl(String authorId) {
    final currentUser = ref.read(currentUserProvider);
    final partner = ref.read(partnerUserProvider);
    if (currentUser != null && currentUser.uid == authorId) {
      return currentUser.avatarUrl;
    }
    if (partner != null && partner.uid == authorId) {
      return partner.avatarUrl;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: (v) => _performSearch(v, isLoadMore: false),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '搜索日记、共记或评论',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.cancel,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('', isLoadMore: false);
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 48),
                ),
                child: const Text(
                  '取消',
                  style: TextStyle(fontSize: 15, color: AppTheme.primaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _performSearch(_keyword, isLoadMore: false),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_keyword.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 54, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            const Text(
              '搜索日记、共记或评论',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_hits.isEmpty) {
      if (_partialErrorMessage != null) {
        return Center(child: _buildPartialError());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sentiment_dissatisfied_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              '未找到与 “$_keyword” 相关的日记',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final warningCount = _partialErrorMessage == null ? 0 : 1;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: warningCount + _hits.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (warningCount == 1 && index == 0) {
          return _buildPartialError(compact: true);
        }
        final hitIndex = index - warningCount;
        if (hitIndex >= _hits.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final hit = _hits[hitIndex];
        final authorName = _getNickname(hit.authorId);
        final avatarUrl = _getAvatarUrl(hit.authorId);

        return Material(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openHit(hit),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarWidget(avatarUrl: avatarUrl, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.selfColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.softSurface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                hit.sourceLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              hit.dateStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildSnippet(hit.content, _keyword),
                      ],
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

  Widget _buildPartialError({bool compact = false}) {
    return Material(
      color: AppTheme.accentSurface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 8 : 14,
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppTheme.accentColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _partialErrorMessage!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _performSearch(_keyword, isLoadMore: false),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
