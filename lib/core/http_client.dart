import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// 面向用户展示的中性错误。内部原因（设备、签名、限流等）绝不
/// 暴露给用户，只说“内容暂时获取失败，请稍后重试”这一类文案。
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.retryable,
    required this.userMessage,
  });

  /// 机器可读的错误码，仅供日志/调试使用。
  final String code;

  /// 是否值得重试（网络抖动、服务端 5xx、429）。
  final bool retryable;

  /// 展示给用户的中性文案。
  final String userMessage;

  factory ApiException.network([String? detail]) => ApiException(
        code: 'network',
        retryable: true,
        userMessage: '网络不太稳定，请稍后重试',
      );

  factory ApiException.server([String? detail]) => ApiException(
        code: 'server',
        retryable: true,
        userMessage: '内容暂时获取失败，请稍后重试',
      );

  factory ApiException.parse([String? detail]) => const ApiException(
        code: 'parse',
        retryable: false,
        userMessage: '内容暂时获取失败，请稍后重试',
      );

  @override
  String toString() => 'ApiException($code, retryable=$retryable): $userMessage';
}

/// 媒体直连探针结果（选源测速用）。
class MediaProbeResult {
  const MediaProbeResult({required this.ok, required this.ms});

  /// 是否可直连：m3u8 须读到 #EXTM3U；mp4 等直链 HEAD 200 即算。
  final bool ok;

  /// 耗时（毫秒）。
  final int ms;
}

/// 带超时与重试的 GET 封装。`client` 可注入，便于测试用假客户端。
class VtvHttpClient {
  VtvHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 探针：验证一个媒体地址是否可直连，并计时。
  /// - m3u8（去 query 后缀 `.m3u8`）：GET 正文须以 #EXTM3U 开头；
  /// - 其他（mp4 等）：HEAD 200 即算可直连。
  /// 单次尝试、不重试，超时按 [timeout] 计（默认 4 秒）。
  /// 与网页端 pickFastestPlaySource 的直连测法一致。
  Future<MediaProbeResult> probeMedia(
    String url, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final cleanPath = url.split('?').first.toLowerCase();
      if (cleanPath.endsWith('.m3u8')) {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(timeout);
        final ms = stopwatch.elapsedMilliseconds;
        if (response.statusCode != 200) {
          return MediaProbeResult(ok: false, ms: ms);
        }
        final ok = response.body.trimLeft().startsWith('#EXTM3U');
        return MediaProbeResult(ok: ok, ms: ms);
      }
      final response = await _client
          .head(Uri.parse(url))
          .timeout(timeout);
      return MediaProbeResult(
        ok: response.statusCode == 200,
        ms: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return MediaProbeResult(ok: false, ms: stopwatch.elapsedMilliseconds);
    }
  }

  /// GET [uri] 并解析 JSON 对象。超时/网络错误按 [kMaxAttempts] 重试。
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    required Duration timeout,
    int maxAttempts = kMaxAttempts,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          throw ApiException.parse('not an object');
        }
        // 5xx / 429 值得重试；4xx 直接失败。
        final retryable =
            response.statusCode >= 500 || response.statusCode == 429;
        if (retryable && attempt < maxAttempts) {
          await Future<void>.delayed(kRetryDelay);
          continue;
        }
        throw ApiException.server('http ${response.statusCode}');
      } on ApiException {
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(kRetryDelay);
          continue;
        }
        throw ApiException.network('timeout');
      } on SocketException catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(kRetryDelay);
          continue;
        }
        throw ApiException.network('socket');
      } on HttpException catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(kRetryDelay);
          continue;
        }
        throw ApiException.network('http');
      } on FormatException catch (e) {
        lastError = e;
        throw ApiException.parse(e.message);
      }
    }
    // 正常情况下循环内不是返回就是抛错；走到这里说明重试耗尽。
    if (lastError is TimeoutException || lastError is SocketException) {
      throw ApiException.network();
    }
    throw ApiException.server();
  }

  void close() => _client.close();
}
