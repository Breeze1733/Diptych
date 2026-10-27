import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/app_user.dart';
import '../models/shared_moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/shared_diary_document.dart';
import 'shared_diary_editor_screen.dart';

class SharedDiaryReadingScreen extends ConsumerStatefulWidget {
  final SharedMoment initialMoment;

  const SharedDiaryReadingScreen({super.key, required this.initialMoment});

  @override
  ConsumerState<SharedDiaryReadingScreen> createState() =>
      _SharedDiaryReadingScreenState();
}

class _SharedDiaryReadingScreenState
    extends ConsumerState<SharedDiaryReadingScreen> {
  late SharedMoment _moment = widget.initialMoment;
  bool _refreshing = false;
  bool _editing = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(quiet: true);
    });
  }

  Future<void> _accept(SharedMoment moment) async {
    if (!mounted) return;
    setState(() => _moment = moment);
    try {
      await CacheService.saveSharedMoment(moment.dateStr, moment);
    } catch (_) {}
    if (mounted) ref.invalidate(sharedMomentProvider(moment.dateStr));
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_refreshing || _editing) return;
    final version = ++_loadVersion;
    setState(() => _refreshing = true);
    try {
      final latest = await ref
          .read(apiServiceProvider)
          .getSharedMomentById(_moment.id);
      if (!mounted || version != _loadVersion) return;
      await _accept(latest);
    } catch (error) {
      if (mounted && !quiet && version == _loadVersion) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('刷新失败，已保留当前共记内容')));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _edit() async {
    if (_refreshing || _editing) return;
    ++_loadVersion;
    setState(() => _editing = true);
    try {
      final saved = await Navigator.of(context).push<SharedMoment>(
        MaterialPageRoute(
          builder: (_) => SharedDiaryEditorScreen(initialMoment: _moment),
        ),
      );
      if (saved != null && mounted) await _accept(saved);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final userA = _byId('A', current, partner);
    final userB = _byId('B', current, partner);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我们的共记'),
        actions: [
          IconButton(
            tooltip: '刷新共记',
            onPressed: _refreshing || _editing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: PageStorageKey('shared-reading-${_moment.id}'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAuthors(userA, userB),
                  const SizedBox(height: 18),
                  SharedDiaryDocument(moment: _moment),
                  const SizedBox(height: 20),
                  Text(
                    '版本 ${_moment.revision} · ${DateHelper.toEditTime(_moment.updatedAt)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: _refreshing || _editing ? null : _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('继续共写'),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthors(AppUser? userA, AppUser? userB) {
    Widget author(String id, AppUser? user) {
      final color = AppTheme.sharedAuthorColor(id);
      return Expanded(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: AvatarWidget(avatarUrl: user?.avatarUrl, size: 30),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                user?.nickname.trim().isNotEmpty == true
                    ? user!.nickname
                    : '用户$id',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        author('A', userA),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            Icons.favorite_rounded,
            size: 18,
            color: AppTheme.accentColor,
          ),
        ),
        author('B', userB),
      ],
    );
  }

  AppUser? _byId(String uid, AppUser? current, AppUser? partner) {
    if (current?.uid == uid) return current;
    if (partner?.uid == uid) return partner;
    return null;
  }
}
