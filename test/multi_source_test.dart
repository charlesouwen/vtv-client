import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/applecms.dart';
import 'package:vtv_client/api/category_map.dart';
import 'package:vtv_client/api/cms_sources.dart';
import 'package:vtv_client/api/hongguo.dart';
import 'package:vtv_client/api/models.dart';
import 'package:vtv_client/api/repository.dart';
import 'package:vtv_client/core/http_client.dart';

import 'helpers/fake_http.dart';

VodItem cmsItem(
  String title, {
  String id = 'cms-1',
  String source = 'ikun',
  String name = 'iKun资源',
  String time = '',
  int hits = 0,
}) =>
    VodItem(
      id: id,
      title: title,
      pic: '',
      year: '2025',
      area: '',
      typeName: '电影',
      remarks: '',
      source: source,
      episodeCount: null,
      sources: [SourceRef(code: source, name: name, id: id)],
      time: time,
      hits: hits,
    );

/// 多源假客户端：默认路由 + ruyi/bfzy 也返回 ikun fixture，
/// 外加测速探针用的 m3u8/mp4 响应。
FakeHttpClient multiSourceFake() {
  final routes = FakeHttpClient.defaultRoutes()
    ..['cj.rycjapi.com'] = ikunSearchFixture()
    ..['bfzyapi.com'] = ikunSearchFixture()
    ..['fast.m3u8'] = '#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:10,\nhttps://x/seg.ts\n'
    ..['bad.m3u8'] = 'not a playlist'
    ..['video.mp4'] = '';
  return FakeHttpClient(routes);
}

/// ikun 搜索 fixture 正文（ruyi/bfzy 复用同一份 fixture 作假数据）。
String ikunSearchFixture() {
  return FakeHttpClient.defaultRoutes()['ikunzyapi.com']!;
}

VtvRepository multiSourceRepo(FakeHttpClient fake) {
  return VtvRepository(
    hongguo: HongguoApi(client: VtvHttpClient(client: fake)),
    appleCms: AppleCmsApi(client: VtvHttpClient(client: fake)),
  );
}

void main() {
  group('18 源注册表', () {
    test('共 18 个源，代号唯一，ikun 默认排第一', () {
      expect(kCmsSources.length, 18);
      final codes = kCmsSources.map((s) => s.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(kCmsSources.first.code, 'ikun');
      expect(kDefaultCmsSource.code, 'ikun');
      expect(kCmsSourcesByCode['bfzy']!.name, '暴风资源');
      expect(kCmsSourcesByCode['ruyi']!.name, '如意资源');
    });

    test('api 地址与网页端 config.js 一致', () {
      expect(
        kCmsSourcesByCode['dyttzy']!.apiBase,
        'http://caiji.dyttzyapi.com/api.php/provide/vod',
      );
      expect(
        kCmsSourcesByCode['ikun']!.apiBase,
        'https://ikunzyapi.com/api.php/provide/vod',
      );
      expect(
        kCmsSourcesByCode['lzi']!.apiBase,
        'https://cj.lziapi.com/api.php/provide/vod/',
      );
      expect(
        kCmsSourcesByCode['ukzy']!.apiBase,
        'https://api.ukuapi88.com/api.php/provide/vod',
      );
      for (final s in kCmsSources) {
        final uri = Uri.tryParse(s.apiBase);
        expect(uri, isNotNull);
        expect(uri!.isAbsolute, isTrue);
        expect(uri.path, contains('api.php/provide/vod'));
      }
    });

    test('分类只用 ikun/ruyi/bfzy 三源（type_id 实测归一）', () {
      expect(kCategorySourceCodes, ['ikun', 'ruyi', 'bfzy']);
      expect(kCmsYearSupported, containsAll(['ikun', 'bfzy']));
      expect(kCmsYearSupported.contains('ruyi'), isFalse);
    });
  });

  group('groupRecommendResults：多源合并去重 + ikun 主键 + 最新在前', () {
    test('同名三源合并为一卡，sources 含三路，主键 ikun', () {
      final cards = VtvRepository.groupRecommendResults([
        cmsItem('碟中谍8', id: 'bf-1', source: 'bfzy', name: '暴风资源'),
        cmsItem('碟中谍8', id: 'ik-1', source: 'ikun', name: 'iKun资源'),
        cmsItem('碟中谍8', id: 'ry-1', source: 'ruyi', name: '如意资源'),
      ]);
      expect(cards.length, 1);
      expect(cards.first.source, 'ikun');
      expect(
        cards.first.sources.map((s) => s.code),
        containsAll(['ikun', 'ruyi', 'bfzy']),
      );
      expect(cards.first.sources.first.code, 'ikun');
    });

    test('不同名各自成卡，按 vod_time 最新在前，空时间排最后', () {
      final cards = VtvRepository.groupRecommendResults([
        cmsItem('旧片', id: 'a', time: '2020-01-01 00:00:00'),
        cmsItem('新片', id: 'b', time: '2026-01-01 00:00:00'),
        cmsItem('无时间', id: 'c', time: ''),
      ]);
      expect(cards.map((c) => c.title), ['新片', '旧片', '无时间']);
    });
  });

  group('groupSearchResults：三源同名合并', () {
    test('ikun/ruyi/bfzy 同名合并为一卡，主键 ikun（无红果时）', () {
      final cards = VtvRepository.groupSearchResults([
        cmsItem('重生1988', id: 'bf-1', source: 'bfzy', name: '暴风资源'),
        cmsItem('重生1988', id: 'ik-1', source: 'ikun', name: 'iKun资源'),
        cmsItem('重生1988', id: 'ry-1', source: 'ruyi', name: '如意资源'),
      ], '重生1988');
      expect(cards.length, 1);
      expect(cards.first.source, 'ikun');
      expect(
        cards.first.sources.map((s) => s.code),
        containsAll(['ikun', 'ruyi', 'bfzy']),
      );
    });
  });

  group('categoryList：三源并行 + 合并去重', () {
    test('动作分类拉 ikun/ruyi/bfzy 三源，结果合并', () async {
      final fake = multiSourceFake();
      final repo = multiSourceRepo(fake);
      final sub = kCategoryTree[TopCategory.movie]!
          .firstWhere((s) => s.label == '动作');
      expect(sub.typeIdFor('ikun'), 6);
      expect(sub.typeIdFor('ruyi'), 6);
      expect(sub.typeIdFor('bfzy'), 21);
      final result = await repo.categoryList(
        sub: sub,
        year: YearFilter.all,
        page: 1,
      );
      expect(result.items, isNotEmpty);
      // 三源都被调到（t 参数按源取各自的 type_id）。
      expect(
        fake.requestedUrls.any((u) => u.contains('ikunzyapi.com')),
        isTrue,
      );
      expect(
        fake.requestedUrls.any((u) => u.contains('cj.rycjapi.com')),
        isTrue,
      );
      expect(
        fake.requestedUrls.any((u) => u.contains('bfzyapi.com')),
        isTrue,
      );
      expect(
        fake.requestedUrls.any((u) => u.contains('t=6')),
        isTrue,
      );
      expect(
        fake.requestedUrls.any((u) => u.contains('t=21')),
        isTrue,
      );
      // 三源同 fixture 去重后不重复标题。
      final titles = result.items.map((e) => e.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('动漫“港台”没有 ikun：只拉 ruyi/bfzy，跳过 ikun', () async {
      final fake = multiSourceFake();
      final repo = multiSourceRepo(fake);
      final sub = kCategoryTree[TopCategory.anime]!
          .firstWhere((s) => s.label == '港台');
      expect(sub.typeIdFor('ikun'), isNull);
      expect(sub.typeIdFor('ruyi'), 32);
      expect(sub.typeIdFor('bfzy'), 43);
      final result = await repo.categoryList(
        sub: sub,
        year: YearFilter.all,
        page: 1,
      );
      expect(result.items, isNotEmpty);
      expect(
        fake.requestedUrls.any((u) => u.contains('ikunzyapi.com')),
        isFalse,
      );
      expect(
        fake.requestedUrls.any((u) => u.contains('cj.rycjapi.com')),
        isTrue,
      );
    });
  });

  group('shortDramaTheme：红果主力 + 暴风补充', () {
    test('红果在前，暴风去重后追加', () async {
      final fake = multiSourceFake();
      final repo = multiSourceRepo(fake);
      final result = await repo.shortDramaTheme('重生', page: 1);
      expect(result.items, isNotEmpty);
      // 红果条目在前。
      final firstHg = result.items.indexWhere((e) => e.source == 'hongguo');
      final firstBfzy = result.items.indexWhere((e) => e.source == 'bfzy');
      expect(firstHg, greaterThanOrEqualTo(0));
      if (firstBfzy >= 0) expect(firstHg, lessThan(firstBfzy));
      // 暴风题材 type_id 59 被调到。
      expect(
        fake.requestedUrls.any(
          (u) => u.contains('bfzyapi.com') && u.contains('t=59'),
        ),
        isTrue,
      );
    });
  });

  group('detail：按来源代号路由到对应源', () {
    test('ikun + bfzy 双源卡，两路 detail 都调到', () async {
      final fake = multiSourceFake();
      final repo = multiSourceRepo(fake);
      final item = VodItem(
        id: 'ik-1',
        title: '测试片',
        pic: '',
        year: '',
        area: '',
        typeName: '电影',
        remarks: '',
        source: 'ikun',
        episodeCount: null,
        sources: [
          const SourceRef(code: 'ikun', name: 'iKun资源', id: '100'),
          const SourceRef(code: 'bfzy', name: '暴风资源', id: '200'),
        ],
      );
      final detail = await repo.detail(item);
      expect(detail.cmsItems.keys, containsAll(['ikun', 'bfzy']));
      expect(
        fake.requestedUrls.any(
          (u) => u.contains('ikunzyapi.com') && u.contains('ids=100'),
        ),
        isTrue,
      );
      expect(
        fake.requestedUrls.any(
          (u) => u.contains('bfzyapi.com') && u.contains('ids=200'),
        ),
        isTrue,
      );
      expect(detail.detailMs.keys, containsAll(['ikun', 'bfzy']));
    });
  });

  group('probeMedia：直连探针', () {
    test('m3u8 读到 #EXTM3U 算可直连', () async {
      final fake = multiSourceFake();
      final client = VtvHttpClient(client: fake);
      final ok = await client.probeMedia('https://example.com/fast.m3u8');
      expect(ok.ok, isTrue);
      expect(ok.ms, greaterThanOrEqualTo(0));
    });

    test('m3u8 正文不是 #EXTM3U 算不可直连', () async {
      final fake = multiSourceFake();
      final client = VtvHttpClient(client: fake);
      final bad = await client.probeMedia('https://example.com/bad.m3u8');
      expect(bad.ok, isFalse);
    });

    test('mp4 HEAD 200 算可直连', () async {
      final fake = multiSourceFake();
      final client = VtvHttpClient(client: fake);
      final mp4 = await client.probeMedia('https://example.com/video.mp4');
      expect(mp4.ok, isTrue);
    });
  });

  group('selectFastest：选源纯逻辑', () {
    test('可直连的取耗时最短的', () {
      final code = VtvRepository.selectFastest([
        const SourceProbe(code: 'ikun', ms: 300, direct: true),
        const SourceProbe(code: 'bfzy', ms: 120, direct: true),
        const SourceProbe(code: 'ruyi', ms: 80, direct: false),
      ], {
        'ikun': 200,
        'bfzy': 150,
        'ruyi': 90,
      });
      expect(code, 'bfzy');
    });

    test('直连全失败时按详情耗时取最快', () {
      final code = VtvRepository.selectFastest([
        const SourceProbe(code: 'ikun', ms: -1, direct: false),
        const SourceProbe(code: 'bfzy', ms: -1, direct: false),
      ], {
        'ikun': 400,
        'bfzy': 150,
      });
      expect(code, 'bfzy');
    });

    test('无任何候选返回 null', () {
      expect(VtvRepository.selectFastest([], {}), isNull);
    });

    test('红果可直连且最快时选中红果', () {
      final code = VtvRepository.selectFastest([
        const SourceProbe(code: 'hongguo', ms: 90, direct: true),
        const SourceProbe(code: 'ikun', ms: 200, direct: true),
      ], {
        'hongguo': 500,
        'ikun': 300,
      });
      expect(code, 'hongguo');
    });
  });

  group('searchAll：18 源并行', () {
    test('搜“重生”调到全部 18 个采集源主机', () async {
      final fake = multiSourceFake();
      final repo = multiSourceRepo(fake);
      final cards = await repo.searchAll('重生');
      expect(cards, isNotEmpty);
      // 18 源主机都被调到（失败的源返回 code 0，静默跳过）。
      var hitCount = 0;
      for (final s in kCmsSources) {
        final host = Uri.parse(s.apiBase).host;
        if (fake.requestedUrls.any((u) => u.contains(host))) hitCount++;
      }
      expect(hitCount, 18);
    });
  });
}
