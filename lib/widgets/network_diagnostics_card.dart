import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/settings_theme.dart';
import '../models/network_diagnostics.dart';
import '../services/network_diagnostics_service.dart';

class NetworkDiagnosticsCard extends StatefulWidget {
  const NetworkDiagnosticsCard({super.key, this.service});

  final NetworkDiagnosticsService? service;

  @override
  State<NetworkDiagnosticsCard> createState() => _NetworkDiagnosticsCardState();
}

class _NetworkDiagnosticsCardState extends State<NetworkDiagnosticsCard>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<NetworkDiagnosticsCard> {
  late final NetworkDiagnosticsService _service;
  NetworkDiagnosticsResult? _result;
  Timer? _cooldownTimer;
  bool _running = false;
  bool _showDetails = false;
  int _completed = 0;
  int _cooldown = 0;
  DateTime? _availableAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NetworkDiagnosticsService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _service.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    if (widget.service == null) {
      _service.dispose();
    } else {
      _service.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (_running || _cooldown > 0) return;
    setState(() {
      _running = true;
      _completed = 0;
      _result = null;
      _showDetails = false;
    });
    final result = await _service.run(
      onProgress: (_, completed) {
        if (mounted) setState(() => _completed = completed);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
      _cooldown = 10;
      _availableAt = DateTime.now().add(const Duration(seconds: 10));
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _availableAt!.difference(DateTime.now()).inMilliseconds;
      setState(
        () => _cooldown = remaining <= 0 ? 0 : (remaining / 1000).ceil(),
      );
      if (_cooldown == 0) timer.cancel();
    });
  }

  Color _resultColor(NetworkDiagnosticsResult result) {
    if (result.cancelled) return SettingsTheme.muted;
    if (result.isUnstable) return SettingsTheme.accent;
    return switch (result.quality) {
      NetworkQuality.fast || NetworkQuality.normal => SettingsTheme.ink,
      NetworkQuality.slow => SettingsTheme.accent,
      NetworkQuality.verySlow => SettingsTheme.danger,
      null => SettingsTheme.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final result = _result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SettingsTheme.accentSurface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.network_check_rounded,
                    color: SettingsTheme.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '检测连通性',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '检查服务器连接与响应耗时',
                        style: TextStyle(
                          fontSize: 12,
                          color: SettingsTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_running) ...[
              LinearProgressIndicator(
                value: null,
                borderRadius: BorderRadius.circular(4),
                minHeight: 4,
                backgroundColor: SettingsTheme.softSurface,
              ),
              const SizedBox(height: 12),
              Text(
                '正在检测 ${(_completed + 1).clamp(1, 3)}/3',
                style: const TextStyle(
                  fontSize: 13,
                  color: SettingsTheme.muted,
                ),
              ),
            ] else if (result != null) ...[
              _buildResult(result),
              const SizedBox(height: 12),
            ] else
              const Text(
                '轻量检测，了解当前连接是否顺畅。',
                style: TextStyle(fontSize: 13, color: SettingsTheme.muted),
              ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final action = _running
                    ? OutlinedButton(
                        onPressed: _service.cancel,
                        child: const Text('取消检测'),
                      )
                    : FilledButton.icon(
                        onPressed: _cooldown > 0 ? null : _start,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(132, 46),
                        ),
                        icon: const Icon(Icons.network_check_rounded, size: 18),
                        label: Text(
                          _cooldown > 0
                              ? '$_cooldown 秒后重测'
                              : result == null
                              ? '开始检测'
                              : '重新检测',
                        ),
                      );
                const hint = Text(
                  '手动开启 · 流量很小',
                  style: TextStyle(fontSize: 11, color: SettingsTheme.muted),
                );
                if (constraints.maxWidth < 280) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      hint,
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    const Expanded(child: hint),
                    const SizedBox(width: 8),
                    action,
                  ],
                );
              },
            ),
            if (result != null && result.samples.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 4),
                  child: Row(
                    children: [
                      const Text('检测详情', style: TextStyle(fontSize: 12)),
                      const Spacer(),
                      Text(
                        '${result.successCount}/${result.samples.length} 次成功',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SettingsTheme.muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _showDetails ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: SettingsTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showDetails) _buildDetails(result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult(NetworkDiagnosticsResult result) {
    final color = _resultColor(result);
    final milliseconds = result.cancelled ? null : result.medianMilliseconds;
    final message = result.cancelled
        ? '检测已停止'
        : result.samples
              .where((sample) => !sample.isSuccess)
              .firstOrNull
              ?.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (milliseconds != null)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: milliseconds == 0 ? '<1' : '$milliseconds',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                      ),
                    ),
                    const TextSpan(
                      text: ' ms',
                      style: TextStyle(
                        fontSize: 13,
                        color: SettingsTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          message ?? '服务器响应 · ${result.successCount} 次请求的中位数',
          style: const TextStyle(
            fontSize: 12,
            color: SettingsTheme.muted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(NetworkDiagnosticsResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        for (var index = 0; index < result.samples.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${index + 1} 次',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SettingsTheme.muted,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    result.samples[index].isSuccess
                        ? '${result.samples[index].elapsedMilliseconds} ms'
                        : result.samples[index].message!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: result.samples[index].isSuccess
                          ? SettingsTheme.ink
                          : SettingsTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          '≤300 ms 快 · ≤800 ms 正常\n≤1500 ms 偏慢 · >1500 ms 很慢',
          style: TextStyle(
            fontSize: 11,
            color: SettingsTheme.muted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '结果包含网络往返与服务器处理，首次请求还可能包含建连时间；分档仅作体验参考。',
          style: TextStyle(
            fontSize: 11,
            color: SettingsTheme.muted,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
