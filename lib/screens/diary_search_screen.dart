import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_theme.dart';
import '../models/moment.dart';
import '../providers/auth_provider.dart';
import '../providers/selected_date_provider.dart';
import '../utils/date_helper.dart';
import '../widgets/avatar_widget.dart';

/// 搜索命中的单个摘要条目
class _SearchHit {
  final Moment moment;
  final String sourceLabel; // "日记" 或 "评论"
  final String content;     // 包含关键词的正文
  final String authorId;    // 该内容的作者

  const _SearchHit({
    required this.moment,
    required this.sourceLabel,
    required this.content,
    required this.authorId,
  });
}

/// 日记搜索页面（参考微信搜索聊天记录）
class DiarySearchScreen extends ConsumerStatefulWidget {
  const DiarySearchScreen({super.key});

  @override
  ConsumerState<DiarySearchScreen> createState() => _DiarySearchScreenState();
}

class _DiarySearchScreenState extends ConsumerState<DiarySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  String _keyword = '';
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;
  String? _errorMessage;
  List<_SearchHit> _hits = [];

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
    _nextCursor = null;
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
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(val, isLoadMore: false);
    });
  }

  Future<void> _performSearch(String query, {bool isLoadMore = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _keyword = '';
        _hits.clear();
        _isSearching = false;
        _isLoadingMore = false;
        _hasMore = false;
        _nextCursor = null;
        _errorMessage = null;
      });
      return;
    }

    if (!isLoadMore) {
      setState(() {
        _keyword = trimmed;
        _hits.clear();
        _isSearching = true;
        _isLoadingMore = false;
        _hasMore = false;
        _nextCursor = null;
        _errorMessage = null;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
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
      final res = await apiService.searchMoments(
        trimmed,
        authorIds,
        limit: 10,
        cursor: isLoadMore ? _nextCursor : null,
      );

      if (!mounted) return;

      final newHits = <_SearchHit>[];
      final qLower = trimmed.toLowerCase();

      for (final m in res.items) {
        // 1. 日记正文匹配
        if (m.feeling.toLowerCase().contains(qLower)) {
          newHits.add(_SearchHit(
            moment: m,
            sourceLabel: '日记',
            content: m.feeling,
            authorId: m.authorId,
          ));
        }
        // 2. 评论匹配
        for (final c in m.comments) {
          if (c.content.toLowerCase().contains(qLower)) {
            newHits.add(_SearchHit(
              moment: m,
              sourceLabel: '评论',
              content: c.content,
              authorId: c.authorId,
            ));
          }
        }
      }

      setState(() {
        if (!isLoadMore) {
          _hits = newHits;
        } else {
          _hits.addAll(newHits);
        }
        _hasMore = res.hasMore;
        _nextCursor = res.nextCursor;
        _isSearching = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _isLoadingMore = false;
        _errorMessage = '搜索失败，请检查网络';
      });
    }
  }

  void _navigateToDate(String dateStr) {
    try {
      final targetDate = DateHelper.parseDateStr(dateStr);
      ref.read(selectedDateProvider.notifier).setDate(targetDate);
      Navigator.pop(context);
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
    final prefixRaw = content.substring(start, matchIndex).replaceAll(RegExp(r'[\r\n]+'), ' ');
    final prefix = (hasMoreBefore ? '...' : '') + prefixRaw;

    // 关键词原字形
    final keywordText = content.substring(matchIndex, matchIndex + keyword.length);

    // 后置文字：最多 _snippetRadius 字，不足实际是多少就多少，绝不填充补空
    final endOfKeyword = matchIndex + keyword.length;
    final remaining = content.length - endOfKeyword;
    final hasMoreAfter = remaining > _snippetRadius;
    final end = hasMoreAfter ? endOfKeyword + _snippetRadius : content.length;
    final suffixRaw = content.substring(endOfKeyword, end).replaceAll(RegExp(r'[\r\n]+'), ' ');
    final suffix = suffixRaw + (hasMoreAfter ? '...' : '');

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          TextSpan(
            text: keywordText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          TextSpan(
            text: suffix,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
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
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
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
                      hintText: '搜索日记内容、感受或评论',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.cancel, size: 18, color: Colors.grey[400]),
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
                  minimumSize: const Size(40, 38),
                ),
                child: const Text('取消', style: TextStyle(fontSize: 15, color: AppTheme.primaryColor)),
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
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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
            Icon(Icons.search, size: 54, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('搜索日记内容、感受或评论', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
      );
    }

    if (_hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sentiment_dissatisfied_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('未找到与 “$_keyword” 相关的日记', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _hits.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 68, color: Color(0xFFEEEEEE)),
      itemBuilder: (context, index) {
        if (index >= _hits.length) {
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

        final hit = _hits[index];
        final authorName = _getNickname(hit.authorId);
        final avatarUrl = _getAvatarUrl(hit.authorId);

        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => _navigateToDate(hit.moment.dateStr),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            Text(
                              authorName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF576B95),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                hit.sourceLabel,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              hit.moment.dateStr,
                              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
}
