import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/applecms.dart';
import 'package:vtv_client/api/hongguo.dart';
import 'package:vtv_client/core/http_client.dart';

import 'helpers/fake_http.dart';

/// 解析测试：全部用 2026-11-24 从 https://411081.xyz 与
/// ikunzyapi.com 拉到的真实响应裁剪版做 fixture
///（test/fixtures/*.json，仅截断列表长度、保留原始结构与字段；
/// playinfo 的 variant 长 URL 截短到 120 字符，不影响解析断言）。
/// 离线可跑、结果确定；live 接口形状变化时改 fixture 即可发现。
void main() {
  group('Hongguo 解析（真实响应 fixture）', () {
    late HongguoApi api;

    setUp(() {
      api = HongguoApi(
        client: VtvHttpClient(client: FakeHttpClient(FakeHttpClient.defaultRoutes())),
      );
    });

    test('recommend：3 条短剧，红果主键字段齐全', () async {
      final result = await api.recommend();
      expect(result.items.length, 3);
      final first = result.items.first;
      expect(first.title, '满院亲戚全是上古大妖');
      expect(first.source, 'hongguo');
      expect(first.typeName, '短剧');
      expect(first.pic, startsWith('https://'));
      expect(result.total, isNonNegative);
    });

    test('search：命中李长生，remarks 带集数', () async {
      final result = await api.search('我李长生');
      expect(result.items.length, 3);
      final first = result.items.first;
      expect(first.id, '7686008653844859966');
      expect(first.title, contains('李长生'));
      expect(first.remarks, '全168集');
      expect(first.episodeCount, 168);
    });

    test('detail：168 集分集，ep-1 对应 episodeNumber 1', () async {
      final series = await api.detail('7686008653844859966');
      expect(series.id, '7686008653844859966');
      expect(series.title, contains('李长生'));
      expect(series.episodes.length, 3); // fixture 截到前 3 集
      final ep1 = series.episodes.first;
      expect(ep1.id, 'ep-1');
      expect(ep1.episodeNumber, 1);
      expect(ep1.playIndex, 0); // playinfo 的 index 是 0 起的
      expect(ep1.title, '第1集');
      expect(ep1.streamUrl, startsWith('https://411081.xyz/hongguo/stream/'));
      expect(series.playbackUnavailable, isFalse);
    });

    test('playinfo：拿到 videoUrl + 16 字节 key + 1080p HEVC', () async {
      final info = await api.playinfo(seriesId: '7686008653844859966', episodeIndex: 0);
      expect(info.videoUrl, startsWith('https://'));
      expect(info.videoUrl, contains('qznovelvod.com'));
      // 16 字节 AES 密钥 hex：32 个十六进制字符。
      expect(info.key, isNotNull);
      expect(info.key!.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(info.key!), isTrue);
      expect(info.encrypted, isTrue);
      expect(info.codec, 'hevc');
      expect(info.quality, '1080p');
      expect(info.width, 1080);
      expect(info.height, 1920);
      expect(info.isVertical, isTrue);
      expect(info.duration, greaterThan(0));
      expect(info.variants.length, 1);
      expect(info.variants.first.codec, 'hevc');
    });

    test('danmaku：time/text 列表', () async {
      final items = await api.danmaku(seriesId: '7686008653844859966', episodeIndex: 0);
      expect(items.length, 5); // fixture 截到前 5 条
      expect(items.first.time, 0.49);
      expect(items.first.text, contains('重生'));
    });
  });

  group('AppleCMS 解析（真实响应 fixture）', () {
    late AppleCmsApi api;

    setUp(() {
      api = AppleCmsApi(
        client: VtvHttpClient(client: FakeHttpClient(FakeHttpClient.defaultRoutes())),
      );
    });

    test('search：列表结构 + vod_play_url 切分', () async {
      final result = await api.search('重生');
      expect(result.items.length, 3);
      final first = result.items.first;
      expect(first.title, '重生密码');
      expect(first.source, 'ikun');
      expect(first.year, '2026');
      expect(first.playGroups.length, 1);
      expect(first.playGroups.first.name, '线路1');
      expect(first.playGroups.first.episodes.length, 2); // fixture 截到前 2 集
      final ep1 = first.playGroups.first.episodes.first;
      expect(ep1.title, '第01集');
      expect(ep1.url, startsWith('https://'));
      expect(ep1.url, endsWith('index.m3u8'));
    });
  });
}
