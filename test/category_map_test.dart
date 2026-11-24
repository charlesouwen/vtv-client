import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/category_map.dart';
import 'package:vtv_client/api/models.dart';

VodItem item(
  String title, {
  String source = 'ikun',
  String year = '',
  String time = '',
  int hits = 0,
}) =>
    VodItem(
      id: title,
      title: title,
      pic: '',
      year: year,
      area: '',
      typeName: '',
      remarks: '',
      source: source,
      episodeCount: null,
      sources: [SourceRef(code: source, name: source, id: title)],
      time: time,
      hits: hits,
    );

void main() {
  group('分类映射表（ikun 实测 type_id）', () {
    test('电影子类：动作 6 / 喜剧 7 / 爱情 8 / 科幻 9 / 恐怖 10 / 剧情 11 / 战争 12 / 动画 22 / 纪录 20', () {
      final subs = {
        for (final s in kCategoryTree[TopCategory.movie]!) s.label: s.typeId,
      };
      expect(subs['动作'], 6);
      expect(subs['喜剧'], 7);
      expect(subs['爱情'], 8);
      expect(subs['科幻'], 9);
      expect(subs['恐怖'], 10);
      expect(subs['剧情'], 11);
      expect(subs['战争'], 12);
      expect(subs['动画'], 22);
      expect(subs['纪录'], 20);
      expect(subs['全部'], isNull);
    });

    test('电视剧子类：国产 23 / 香港 24 / 韩国 25 / 欧美 26 / 台湾 27 / 日本 28 / 海外 29 / 泰国 30', () {
      final subs = {
        for (final s in kCategoryTree[TopCategory.tv]!) s.label: s.typeId,
      };
      expect(subs['国产'], 23);
      expect(subs['香港'], 24);
      expect(subs['韩国'], 25);
      expect(subs['欧美'], 26);
      expect(subs['台湾'], 27);
      expect(subs['日本'], 28);
      expect(subs['海外'], 29);
      expect(subs['泰国'], 30);
    });

    test('综艺 31-34 / 动漫 35-37', () {
      final variety = {
        for (final s in kCategoryTree[TopCategory.variety]!) s.label: s.typeId,
      };
      expect(variety['大陆'], 31);
      expect(variety['港台'], 32);
      expect(variety['日韩'], 33);
      expect(variety['欧美'], 34);
      final anime = {
        for (final s in kCategoryTree[TopCategory.anime]!) s.label: s.typeId,
      };
      expect(anime['国产'], 35);
      expect(anime['欧美'], 36);
      expect(anime['日韩'], 37);
    });

    test('短剧题材 9 个，走红果 search，不占 type_id', () {
      expect(kShortDramaThemes, [
        '重生',
        '穿越',
        '现代言情',
        '反转爽文',
        '女恋总裁',
        '闪婚离婚',
        '都市脑洞',
        '古装仙侠',
        'AI漫剧',
      ]);
      expect(
        kCategoryTree[TopCategory.shortDrama]!
            .where((s) => s.label != '全部')
            .map((s) => s.label),
        kShortDramaThemes,
      );
    });
  });

  group('年份过滤（客户端）', () {
    test('指定年份：红果豁免，ikun 按 year 留', () {
      final items = [
        item('红果剧', source: 'hongguo'),
        item('当年剧', year: '2026'),
        item('往年剧', year: '2024'),
      ];
      final kept = filterCategoryByYear(items, YearFilter.y2026);
      expect(kept.map((e) => e.title), ['红果剧', '当年剧']);
    });

    test('“更早”：只留 vod_year ≤ 2021，红果不豁免', () {
      final items = [
        item('红果剧', source: 'hongguo'),
        item('老剧', year: '2021'),
        item('更老剧', year: '2019'),
        item('新剧', year: '2022'),
        item('无年份剧', year: ''),
      ];
      final kept = filterCategoryByYear(items, YearFilter.earlier);
      expect(kept.map((e) => e.title), ['老剧', '更老剧']);
    });

    test('全部：不过滤', () {
      final items = [item('A', year: '2026'), item('B', source: 'hongguo')];
      expect(filterCategoryByYear(items, YearFilter.all), items);
    });
  });

  group('排序（客户端）', () {
    test('最新：vod_time 降序，空时间排最后；红果组在前', () {
      final items = [
        item('旧', time: '2026-11-21 12:11:25'),
        item('无时间'),
        item('红果剧', source: 'hongguo'),
        item('新', time: '2026-11-22 20:39:20'),
      ];
      final sorted = sortCategoryItems(items, CategorySort.latest);
      expect(sorted.map((e) => e.title), ['红果剧', '新', '旧', '无时间']);
    });

    test('最热：vod_hits 降序；红果组在前', () {
      final items = [
        item('冷门', hits: 10),
        item('热门', hits: 3856),
        item('红果剧', source: 'hongguo'),
      ];
      final sorted = sortCategoryItems(items, CategorySort.hottest);
      expect(sorted.map((e) => e.title), ['红果剧', '热门', '冷门']);
    });
  });
}
