import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/applecms.dart';
import 'package:vtv_client/api/hongguo.dart';
import 'package:vtv_client/api/repository.dart';
import 'package:vtv_client/core/http_client.dart';
import 'package:vtv_client/main.dart';

import 'helpers/fake_http.dart';

/// 自适应验收 + 最小链路验收。
///
/// 方法：全部用假 HTTP 客户端（test/helpers/fake_http.dart），返回
/// 2026-11-24 从真实接口拉到的响应裁剪版 fixture；图片请求用
/// FakeImageHttpOverrides 返回 1x1 PNG，不走真实网络。
/// 不真播出画面：播放器只断言到 playinfo 一步（videoUrl+key 的
/// 解析断言见 test/api_parsing_test.dart，链路断言见下方点播测试）。
void main() {
  late FakeHttpClient fake;
  late VtvRepository repository;

  setUp(() {
    HttpOverrides.global = FakeImageHttpOverrides();
    fake = FakeHttpClient(FakeHttpClient.defaultRoutes());
    repository = VtvRepository(
      hongguo: HongguoApi(client: VtvHttpClient(client: fake)),
      appleCms: AppleCmsApi(client: VtvHttpClient(client: fake)),
    );
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VtvApp(repository: repository));
    await tester.pumpAndSettle();
  }

  int gridColumns(WidgetTester tester) {
    final grid = tester.widget<GridView>(
      find.byKey(const Key('short-drama-grid')),
    );
    final delegate = grid.gridDelegate;
    expect(
      delegate,
      isA<SliverGridDelegateWithFixedCrossAxisCount>(),
    );
    return (delegate as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;
  }

  group('自适应：导航形态与卡片列数随宽度变化、无溢出', () {
    testWidgets('手机 390x844：底部导航 + 3 列', (tester) async {
      await pumpApp(tester, const Size(390, 844));
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(gridColumns(tester), 3);
      expect(find.text('满院亲戚全是上古大妖'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('平板 800x1280：底部导航 + 4 列', (tester) async {
      await pumpApp(tester, const Size(800, 1280));
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(gridColumns(tester), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('电视窗口 1920x1080：左侧导航栏 + 6 列', (tester) async {
      await pumpApp(tester, const Size(1920, 1080));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(gridColumns(tester), 6);
      expect(tester.takeException(), isNull);
    });
  });

  group('最小链路：首页出卡 → 点卡进详情 → 点第 1 集调 playinfo', () {
    testWidgets('点第 1 集调到 playinfo，拿到 videoUrl+key 的播放信息', (tester) async {
      await pumpApp(tester, const Size(390, 844));

      // 首页短剧列表出卡。
      expect(find.text('满院亲戚全是上古大妖'), findsOneWidget);

      // 点卡片进详情占位页。
      await tester.tap(find.text('满院亲戚全是上古大妖'));
      await tester.pumpAndSettle();
      expect(find.text('选集（3集）'), findsOneWidget);
      expect(find.text('第1集'), findsOneWidget);
      expect(
        fake.requestedUrls.any((u) => u.contains('hongguo/detail')),
        isTrue,
      );

      // 点第 1 集：调 playinfo（index=0），播放页拿到播放信息。
      await tester.tap(find.text('第1集'));
      await tester.pumpAndSettle();
      final playinfoUrls = fake.requestedUrls
          .where((u) => u.contains('hongguo/playinfo'))
          .toList();
      // 两次：一次是详情加载后后台测速探针（红果参与测速，探第 1 集），
      // 一次是点第 1 集进播放页；两次都是 index=0、同一 series_id。
      expect(playinfoUrls.length, 2);
      for (final u in playinfoUrls) {
        expect(u, contains('index=0'));
        expect(u, contains('series_id=7686008653844859966'));
      }
      // 播放页已拿到 playinfo：清晰度芯片 1080p · hevc 出现，
      // 即 videoUrl + key 已到手（解析断言见 api_parsing_test）。
      expect(find.byKey(const Key('playinfo-chip')), findsOneWidget);
      expect(find.text('1080p · hevc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
