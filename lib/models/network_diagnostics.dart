enum NetworkFailure {
  timeout,
  connection,
  tls,
  rateLimited,
  challenge,
  accessDenied,
  server,
  invalidResponse,
  cachedResponse,
}

enum NetworkQuality {
  fast('快'),
  normal('正常'),
  slow('偏慢'),
  verySlow('很慢');

  const NetworkQuality(this.label);
  final String label;

  static NetworkQuality fromMilliseconds(int milliseconds) {
    if (milliseconds <= 300) return fast;
    if (milliseconds <= 800) return normal;
    if (milliseconds <= 1500) return slow;
    return verySlow;
  }
}

class NetworkProbeSample {
  const NetworkProbeSample.success(this.elapsedMilliseconds)
    : failure = null,
      message = null;

  const NetworkProbeSample.failed(this.failure, this.message)
    : elapsedMilliseconds = null;

  final int? elapsedMilliseconds;
  final NetworkFailure? failure;
  final String? message;
  bool get isSuccess => elapsedMilliseconds != null;

  bool get shouldStop => switch (failure) {
    NetworkFailure.rateLimited ||
    NetworkFailure.challenge ||
    NetworkFailure.accessDenied ||
    NetworkFailure.cachedResponse => true,
    _ => false,
  };
}

class NetworkDiagnosticsResult {
  NetworkDiagnosticsResult(
    Iterable<NetworkProbeSample> samples, {
    this.cancelled = false,
  }) : samples = List.unmodifiable(samples);

  final List<NetworkProbeSample> samples;
  final bool cancelled;

  int get successCount => samples.where((sample) => sample.isSuccess).length;
  bool get isUnstable => successCount > 0 && successCount < samples.length;

  int? get medianMilliseconds {
    final times =
        samples
            .where((sample) => sample.isSuccess)
            .map((sample) => sample.elapsedMilliseconds!)
            .toList()
          ..sort();
    if (times.isEmpty) return null;
    final middle = times.length ~/ 2;
    return times.length.isOdd
        ? times[middle]
        : ((times[middle - 1] + times[middle]) / 2).round();
  }

  NetworkQuality? get quality {
    final milliseconds = medianMilliseconds;
    if (cancelled || isUnstable || milliseconds == null) return null;
    return NetworkQuality.fromMilliseconds(milliseconds);
  }

  String get label {
    if (cancelled) return '已取消';
    if (isUnstable) return '连接不稳定';
    if (quality != null) return quality!.label;
    if (samples.isEmpty) return '尚未检测';
    return switch (samples.last.failure) {
      NetworkFailure.timeout => '响应超时',
      NetworkFailure.connection => '连接失败',
      NetworkFailure.tls => '安全连接失败',
      NetworkFailure.rateLimited => '请求受限',
      NetworkFailure.challenge || NetworkFailure.accessDenied => '访问受限',
      NetworkFailure.server => '服务器异常',
      NetworkFailure.cachedResponse => '缓存响应',
      _ => '响应异常',
    };
  }
}
