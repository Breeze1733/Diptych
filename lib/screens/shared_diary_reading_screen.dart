import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../models/shared_moment.dart';
import '../providers/auth_provider.dart';
import '../providers/day_moment_provider.dart';
import '../services/cache_service.dart';
import '../utils/date_helper.dart';
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
  bool _photosExpanded = false;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('我们的共记'),
        actions: [
          if (_moment.blocks
                  .where((b) => b.type == SharedMomentBlockType.image)
                  .length >
              6)
            IconButton(
              tooltip: _photosExpanded ? '收起图片列表' : '展开图片列表',
              onPressed: _refreshing || _editing
                  ? null
                  : () => setState(() => _photosExpanded = !_photosExpanded),
              icon: Icon(
                _photosExpanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
              ),
            ),
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
                  SharedDiaryDocument(
                    moment: _moment,
                    photosExpanded: _photosExpanded,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    DateHelper.toEditTime(_moment.updatedAt),
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
}
