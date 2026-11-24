import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/applecms.dart';
import 'package:vtv_client/api/hongguo.dart';
import 'package:vtv_client/api/models.dart';
import 'package:vtv_client/api/repository.dart';
import 'package:vtv_client/core/http_client.dart';

import 'helpers/fake_http.dart';

VodItem hongguoItem(String title, {String id = 'hg-1'}) => VodItem(
      id: id,
      title: title,
      pic: '',
      year: '',
      area: '',
      typeName: '短剧',
      remarks: '全100集',
      source: 'hongguo',
      episodeCount: 100,
      sources: [SourceRef(code: 'hongguo', name: '红果短剧', id: id)],
    );

VodItem cmsItem(String title, {String id = 'cms-1'}) => VodItem(
      id: id,
      title: title,
      pic: '',
      year: '',
      area: '',
      typeName: '短剧',
      remarks: '全100集',
      source: 'ikun',
      episodeCount: 100,
      sources: [SourceRef(code: 'ikun', name: 'ikun', id: id)],
    );

void main() {
  group('groupSearchResults：分组去重 + 红果主键 + 红果优先 + 零重叠去掉', () {
    test('同名合并为一卡，红果做主键，sources 含两路', () {
      final cards = VtvRepository.groupSearchResults([
        cmsItem('重生1988', id: 'cms-9'),
        hongguoItem('重生1988', id: 'hg-9'),
      ], '重生1988');
      expect(cards.length, 1);
      expect(cards.first.source, 'hongguo');
      expect(cards.first.id, 'hg-9');
      expect(cards.first.sources.map((s) => s.code), containsAll(['hongguo', 'ikun']));
      expect(cards.first.sources.first.code, 'hongguo');
    });

    test('同等相关性红果组在前', () {
      // 两条都是“包含命中”（score 1）：关键词出现在标题中间，
      // 不是开头命中，相关性同级，红果组在前。
      final cards = VtvRepository.groupSearchResults([
        cmsItem('大话重生', id: 'cms-1'),
        hongguoItem('都市重生路', id: 'hg-2'),
      ], '重生');
      expect(cards.map((c) => c.title), ['都市重生路', '大话重生']);
      expect(cards.first.source, 'hongguo');
    });

    test('精确匹配最前，其次开头命中，再次包含命中', () {
      final cards = VtvRepository.groupSearchResults([
        cmsItem('大话重生', id: 'cms-1'),
        cmsItem('重生', id: 'cms-2'),
        cmsItem('重生密码', id: 'cms-3'),
      ], '重生');
      expect(cards.map((c) => c.title), ['重生', '重生密码', '大话重生']);
    });

    test('标题与关键词零重叠的去掉', () {
      final cards = VtvRepository.groupSearchResults([
        cmsItem('重生密码'),
        cmsItem('完全无关的电影'),
        hongguoItem('都市爱情故事'),
      ], '重生');
      expect(cards.map((c) => c.title), ['重生密码']);
    });

    test('标点/空白差异的同名仍合并', () {
      final cards = VtvRepository.groupSearchResults([
        cmsItem('重生1988，从做倒爷开始起家', id: 'cms-1'),
        hongguoItem('重生1988从做倒爷开始起家', id: 'hg-1'),
      ], '重生1988');
      expect(cards.length, 1);
      expect(cards.first.source, 'hongguo');
    });
  });

  group('searchAll（假 HTTP 客户端 + 真实 fixture）', () {
    test('搜“重生”：红果与 ikun 并行，结果按相关性排', () async {
      final fake = FakeHttpClient(FakeHttpClient.defaultRoutes());
      final repo = VtvRepository(
        hongguo: HongguoApi(client: VtvHttpClient(client: fake)),
        appleCms: AppleCmsApi(client: VtvHttpClient(client: fake)),
      );
      final cards = await repo.searchAll('重生');
      // ikun“重生密码”开头命中在前；红果三条均为包含命中，
      // 其中与 ikun“我真没想重生啊”同名？不同名，各自成卡。
      expect(cards, isNotEmpty);
      expect(cards.first.title, '重生密码');
      // 红果卡在同等相关性下排在 ikun 卡前面。
      final hongguoIndices = <int>[];
      final cmsIndices = <int>[];
      for (var i = 0; i < cards.length; i++) {
        if (cards[i].source == 'hongguo') {
          hongguoIndices.add(i);
        } else {
          cmsIndices.add(i);
        }
      }
      expect(hongguoIndices.first, lessThan(cmsIndices.last));
      // 两路都被调到。
      expect(fake.requestedUrls.any((u) => u.contains('hongguo/search')), isTrue);
      expect(fake.requestedUrls.any((u) => u.contains('ikunzyapi.com')), isTrue);
    });

    test('空关键词直接返回空，不发请求', () async {
      final fake = FakeHttpClient(FakeHttpClient.defaultRoutes());
      final repo = VtvRepository(
        hongguo: HongguoApi(client: VtvHttpClient(client: fake)),
        appleCms: AppleCmsApi(client: VtvHttpClient(client: fake)),
      );
      expect(await repo.searchAll('   '), isEmpty);
      expect(fake.requestedUrls, isEmpty);
    });
  });
}
