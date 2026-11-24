import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vtv_client/api/applecms.dart';
import 'package:vtv_client/api/hongguo.dart';
import 'package:vtv_client/api/models.dart';
import 'package:vtv_client/api/repository.dart';
import 'package:vtv_client/core/http_client.dart';
import 'package:vtv_client/ui/category_page.dart';
import 'package:vtv_client/ui/detail_page.dart';
import 'package:vtv_client/ui/search_page.dart';

import 'helpers/fake_http.dart';

/// M1 页面 widget 测试：分类 / 搜索 / 详情 / 播放。
/// 全部用假 HTTP + fixture，不走真实网络、不真播出画面。
void main() {
  late FakeHttpClient fake;
  late VtvRepository repository;

  setUp(() {
    HttpOverrides.global = FakeImageHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    fake = FakeHttpClient(FakeHttpClient.defaultRoutes());
    repository = VtvRepository(
      hongguo: HongguoApi(client: VtvHttpClient(client: fake)),
      appleCms: AppleCmsApi(client: VtvHttpClient(client: fake)),
    );
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: page)),
    );
    await tester.pumpAndSettle();
  }

  VodItem liChangsheng() => VodItem(
        id: '7686008653844859966',
        title: '我李长生重回八零，赶山狩猎养妻女',
        pic: '',
        year: '',
        area: '',
        typeName: '短剧',
        remarks: '全168集',
        source: 'hongguo',
        episodeCount: 168,
        sources: const [
          SourceRef(code: 'hongguo', name: '红果短剧', id: '7686008653844859966'),
          SourceRef(code: 'ikun', name: 'ikun', id: '70980'),
        ],
      );

  group('分类页', () {
    testWidgets('默认电影分类出卡；切子类/年份/排序仍有卡片、无溢出',
        (tester) async {
      await pumpPage(tester, CategoryPage(repository: repository));

      expect(find.text('重生密码'), findsOneWidget);
      expect(find.byKey(const Key('category-grid')), findsOneWidget);

      // 切子类：动作（ikun type_id 6）。
      await tester.tap(find.text('动作'));
      await tester.pumpAndSettle();
      expect(find.text('重生密码'), findsOneWidget);
      expect(
        fake.requestedUrls.any((u) => u.contains('t=6')),
        isTrue,
      );

      // 切年份：2026（ikun year 参数服务端筛）。
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      expect(find.text('重生密码'), findsOneWidget);
      expect(
        fake.requestedUrls.any((u) => u.contains('year=2026')),
        isTrue,
      );

      // 切排序：最热。
      await tester.tap(find.text('最热'));
      await tester.pumpAndSettle();
      expect(find.text('重生密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('短剧大类：全部走红果推荐，题材走红果搜索', (tester) async {
      await pumpPage(tester, CategoryPage(repository: repository));

      await tester.tap(find.text('短剧'));
      await tester.pumpAndSettle();
      expect(find.text('满院亲戚全是上古大妖'), findsOneWidget);

      await tester.tap(find.text('重生'));
      await tester.pumpAndSettle();
      expect(find.text('我李长生重回八零，赶山狩猎养妻女'), findsOneWidget);
      expect(
        fake.requestedUrls.any((u) => u.contains('hongguo/search')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('平板 800x1280 与电视窗口 1920x1080 无溢出', (tester) async {
      await pumpPage(
        tester,
        CategoryPage(repository: repository),
        size: const Size(800, 1280),
      );
      expect(find.text('重生密码'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpPage(
        tester,
        CategoryPage(repository: repository),
        size: const Size(1920, 1080),
      );
      expect(find.text('重生密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('搜索页', () {
    testWidgets('搜“重生”：分组标题出现，红果卡在前', (tester) async {
      await pumpPage(tester, SearchPage(repository: repository));

      expect(find.text('热搜'), findsOneWidget);
      expect(find.byKey(const Key('hot-search')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('search-field')),
        '重生',
      );
      await tester.tap(find.byKey(const Key('search-submit')));
      await tester.pumpAndSettle();

      expect(find.text('命中'), findsOneWidget);
      expect(find.text('猜你喜欢'), findsOneWidget);
      // “命中”组：以“重生”开头的重生密码。
      expect(find.text('重生密码'), findsOneWidget);
      // “猜你喜欢”组内红果卡在前：八一重生（红果）在我真没想重生啊（ikun）之前。
      // （李长生标题里“重生”二字不连续，按仓库零重叠规则已被去掉。）
      final hgTop = tester.getTopLeft(
        find.text('八一重生：赶山踏雪护妻儿第二季'),
      );
      final cmsTop = tester.getTopLeft(find.text('我真没想重生啊'));
      expect(hgTop.dy, lessThan(cmsTop.dy));
      expect(tester.takeException(), isNull);

      // 清空回到搜索首页：历史里有刚搜过的“重生”。
      await tester.tap(find.byKey(const Key('search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('热搜'), findsOneWidget);
      expect(find.text('重生'), findsWidgets);
    });
  });

  group('详情页 + 播放页', () {
    testWidgets('源列表出现、选集可点、点集进播放页控制栏与选集列表出现',
        (tester) async {
      await pumpPage(tester, DetailPage(item: liChangsheng(), repository: repository));

      // 详情：源列表（红果在前，短剧规则）+ 红果选集。
      expect(find.byKey(const Key('source-list')), findsOneWidget);
      expect(find.byKey(const Key('source-hongguo')), findsOneWidget);
      expect(find.byKey(const Key('source-ikun')), findsOneWidget);
      expect(find.text('选集（3集）'), findsOneWidget);
      expect(find.text('第1集'), findsOneWidget);
      // 相关推荐区出现（同类型，红果推荐）。
      expect(find.text('相关推荐'), findsOneWidget);

      // 切到 ikun 源：采集源分集标题出现。
      await tester.tap(find.byKey(const Key('source-ikun')));
      await tester.pumpAndSettle();
      expect(find.text('第01集'), findsOneWidget);

      // 切回红果，点第 1 集进播放页。
      await tester.tap(find.byKey(const Key('source-hongguo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第1集'));
      await tester.pumpAndSettle();

      // 播放页：调到 playinfo，控制栏与选集列表出现。
      expect(
        fake.requestedUrls.any((u) => u.contains('hongguo/playinfo')),
        isTrue,
      );
      expect(find.byKey(const Key('player-controls')), findsOneWidget);
      expect(find.byKey(const Key('play-pause-button')), findsOneWidget);
      expect(find.byKey(const Key('seek-slider')), findsOneWidget);
      expect(find.byKey(const Key('speed-button')), findsOneWidget);
      expect(find.byKey(const Key('volume-slider')), findsOneWidget);
      expect(find.byKey(const Key('fullscreen-button')), findsOneWidget);
      expect(find.byKey(const Key('danmaku-toggle')), findsOneWidget);
      expect(find.byKey(const Key('player-episode-list')), findsOneWidget);
      expect(find.text('选集（3集）'), findsOneWidget);
      expect(find.byKey(const Key('playinfo-chip')), findsOneWidget);
      expect(find.text('1080p · hevc'), findsOneWidget);
      // 竖屏短剧：playinfo 1080x1920，竖屏标识出现。
      expect(find.text('竖屏'), findsOneWidget);
      // 弹幕已拉到（渲染窗口逻辑见 test/danmaku_test.dart；
      // 测试环境建不出真播放器，弹幕层随 Video 一起不渲染）。
      expect(
        fake.requestedUrls.any((u) => u.contains('hongguo/danmaku')),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('speed-button')));
      await tester.pumpAndSettle();
      expect(find.text('1.5x'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('vtv_rate'), 1.5);

      // 全屏切换：选集列表收起，再点恢复。
      await tester.tap(find.byKey(const Key('fullscreen-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-episode-list')), findsNothing);
      await tester.tap(find.byKey(const Key('fullscreen-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-episode-list')), findsOneWidget);

      // 播放页内点第 2 集：调 playinfo index=1。
      await tester.tap(find.text('第2集'));
      await tester.pumpAndSettle();
      final playinfoUrls = fake.requestedUrls
          .where((u) => u.contains('hongguo/playinfo'))
          .toList();
      expect(playinfoUrls.any((u) => u.contains('index=1')), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
