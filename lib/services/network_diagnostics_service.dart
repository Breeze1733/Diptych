import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/api_config.dart';
import '../models/network_diagnostics.dart';

/// Measures a small, read-only application response, including connection setup.
/// No retries or background polling; all requests in a run share one client.
class NetworkDiagnosticsService {
  NetworkDiagnosticsService({
    http.Client Function()? clientFactory,
    Uri? endpoint,
    this.sampleTimeout = const Duration(seconds: 3),
    this.interval = const Duration(milliseconds: 500),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _endpoint =
           endpoint ?? Uri.parse('${ApiConfig.apiBaseUrl}/version/latest');

  static const sampleCount = 3;
  static const _maxBodyBytes = 16 * 1024;
  final http.Client Function() _clientFactory;
  final Uri _endpoint;
  final Duration sampleTimeout;
  final Duration interval;
  _ProbeRun? _activeRun;
  bool _disposed = false;

  Future<NetworkDiagnosticsResult> run({
    void Function(NetworkProbeSample sample, int completed)? onProgress,
  }) async {
    if (_disposed) {
      throw StateError('Network diagnostics service is disposed.');
    }
    if (_activeRun != null) {
      throw StateError('A network test is already running.');
    }

    final run = _ProbeRun(_clientFactory());
    _activeRun = run;
    final samples = <NetworkProbeSample>[];
    try {
      for (var index = 0; index < sampleCount; index++) {
        if (run.isCancelled) break;
        NetworkProbeSample sample;
        try {
          sample = await _awaitProbe(run, index);
        } on _ProbeCancelled {
          break;
        } on TimeoutException {
          if (run.isCancelled) break;
          run.client.close();
          // A timed-out response may still own the previous connection.
          if (index + 1 < sampleCount) run.client = _clientFactory();
          sample = const NetworkProbeSample.failed(
            NetworkFailure.timeout,
            '服务器在 3 秒内没有完成响应',
          );
        } on HandshakeException {
          sample = const NetworkProbeSample.failed(
            NetworkFailure.tls,
            '无法建立安全连接，请检查设备时间或稍后重试',
          );
        } on SocketException {
          sample = const NetworkProbeSample.failed(
            NetworkFailure.connection,
            '无法连接日记服务器，请检查网络后重试',
          );
        } on http.ClientException {
          sample = const NetworkProbeSample.failed(
            NetworkFailure.connection,
            '连接中断，请稍后重试',
          );
        } on FormatException {
          sample = const NetworkProbeSample.failed(
            NetworkFailure.invalidResponse,
            '服务器没有返回预期的检测结果',
          );
        } catch (_) {
          sample = const NetworkProbeSample.failed(
            NetworkFailure.invalidResponse,
            '检测未完成，请稍后重试',
          );
        }

        if (run.isCancelled) break;
        samples.add(sample);
        onProgress?.call(sample, samples.length);
        if (sample.shouldStop || run.isCancelled) break;
        if (index + 1 < sampleCount) {
          // The pause is outside the stopwatch and is also cancellable.
          final pause = Completer<void>();
          final timer = Timer(interval, pause.complete);
          try {
            await Future.any([pause.future, run.cancelled.future]);
          } finally {
            timer.cancel();
          }
        }
      }
      return NetworkDiagnosticsResult(samples, cancelled: run.isCancelled);
    } finally {
      run.client.close();
      if (identical(_activeRun, run)) _activeRun = null;
    }
  }

  Future<NetworkProbeSample> _awaitProbe(_ProbeRun run, int index) async {
    final timedOut = Completer<NetworkProbeSample>();
    final timer = Timer(sampleTimeout, () {
      timedOut.completeError(TimeoutException('Probe response timed out.'));
    });
    try {
      return await Future.any([
        _probe(run.client, index),
        timedOut.future,
        run.cancelled.future.then<NetworkProbeSample>(
          (_) => throw const _ProbeCancelled(),
        ),
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<NetworkProbeSample> _probe(http.Client client, int index) async {
    final uri = _endpoint.replace(
      queryParameters: {
        ..._endpoint.queryParameters,
        '_network_probe': '${DateTime.now().microsecondsSinceEpoch}_$index',
      },
    );
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Cache-Control': 'no-cache, no-store',
      });

    final stopwatch = Stopwatch()..start();
    final response = await client.send(request);
    if (response.headers['cf-mitigated']?.toLowerCase() == 'challenge') {
      return const NetworkProbeSample.failed(
        NetworkFailure.challenge,
        '请求被 Cloudflare 安全验证拦截，请稍后重试',
      );
    }
    if (response.statusCode == 429) {
      return const NetworkProbeSample.failed(
        NetworkFailure.rateLimited,
        '服务器暂时限制请求频率，请稍后重试',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const NetworkProbeSample.failed(
        NetworkFailure.accessDenied,
        '检测请求被拒绝，请检查服务器访问设置',
      );
    }
    if (response.statusCode != 200) {
      return NetworkProbeSample.failed(
        response.statusCode >= 500
            ? NetworkFailure.server
            : NetworkFailure.invalidResponse,
        '服务器返回异常状态（${response.statusCode}）',
      );
    }

    final cacheStatus = response.headers['cf-cache-status']?.toUpperCase();
    final age = int.tryParse(response.headers['age'] ?? '') ?? 0;
    if (const {'HIT', 'STALE', 'UPDATING'}.contains(cacheStatus) || age > 0) {
      return const NetworkProbeSample.failed(
        NetworkFailure.cachedResponse,
        '检测响应来自缓存，暂不能判断后端响应耗时',
      );
    }
    if ((response.contentLength ?? 0) > _maxBodyBytes) {
      throw const FormatException('Unexpectedly large probe response.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxBodyBytes) {
        throw const FormatException('Probe response exceeds the size limit.');
      }
      bytes.addAll(chunk);
    }
    stopwatch.stop();
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map || body['ok'] != true || body['data'] is! Map) {
      throw const FormatException('Invalid version response.');
    }
    final data = body['data'] as Map;
    if (data['version'] is! String || data['version_code'] is! num) {
      throw const FormatException('Missing version fields.');
    }
    return NetworkProbeSample.success(stopwatch.elapsedMilliseconds);
  }

  void cancel() {
    final run = _activeRun;
    if (run == null || run.isCancelled) return;
    run.cancelled.complete();
    run.client.close();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

class _ProbeRun {
  _ProbeRun(this.client);
  http.Client client;
  final cancelled = Completer<void>();
  bool get isCancelled => cancelled.isCompleted;
}

class _ProbeCancelled implements Exception {
  const _ProbeCancelled();
}
