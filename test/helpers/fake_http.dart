import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 测试用假 HTTP 客户端（package:http 层）：
/// 按 URL 子串匹配，返回 test/fixtures 下的真实响应裁剪版，
/// 并记录所有请求过的 URL，供断言调用链使用。
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._routes);

  final Map<String, String> _routes;

  /// 按请求顺序记录的完整 URL。
  final List<String> requestedUrls = [];

  static Map<String, String> defaultRoutes() {
    String fixture(String name) =>
        File('test/fixtures/$name').readAsStringSync();
    return <String, String>{
      'hongguo/recommend': fixture('hongguo_recommend.json'),
      'hongguo/search': fixture('hongguo_search.json'),
      'hongguo/detail': fixture('hongguo_detail.json'),
      'hongguo/playinfo': fixture('hongguo_playinfo.json'),
      'hongguo/danmaku': fixture('hongguo_danmaku.json'),
      // ikun：搜索与详情共用同一 AppleCMS 列表结构。
      'ikunzyapi.com': fixture('ikun_search.json'),
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requestedUrls.add(url);
    for (final entry in _routes.entries) {
      if (url.contains(entry.key)) {
        final bytes = utf8.encode(entry.value);
        return http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{"code":0}')), 200,
        request: request);
  }
}

/// 让 Image.network 在测试里不走真实网络：所有图片请求都返回
/// 一张 1x1 透明 PNG。
class FakeImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FakeImageHttpClient();
  }
}

class _FakeImageHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeImageRequest();
}

class _FakeImageRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _FakeImageResponse();
}

class _FakeImageResponse extends Fake implements HttpClientResponse {
  static const List<int> _png = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
    0x42, 0x60, 0x82,
  ];

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_png).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// 读 fixture JSON。
Map<String, dynamic> readFixture(String name) {
  return jsonDecode(File('test/fixtures/$name').readAsStringSync())
      as Map<String, dynamic>;
}
