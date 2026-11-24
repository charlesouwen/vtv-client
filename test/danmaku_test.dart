import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/models.dart';
import 'package:vtv_client/ui/player_page.dart';

/// 弹幕渲染窗口（visibleDanmaku 纯函数）：按播放时间取前后 5 秒内、
/// 最多 5 条。暂停冻结是位置驱动的——position 流停住，窗口就不动。
void main() {
  const items = [
    DanmakuItem(time: 0.49, text: '开局留住了我'),
    DanmakuItem(time: 1.29, text: '搞笑了'),
    DanmakuItem(time: 2.0, text: '第三条'),
    DanmakuItem(time: 3.0, text: '第四条'),
    DanmakuItem(time: 4.0, text: '第五条'),
    DanmakuItem(time: 4.5, text: '第六条'),
    DanmakuItem(time: 9.0, text: '后面的'),
    DanmakuItem(time: 20.0, text: '很后面的'),
  ];

  test('0 秒时：尚未到时间的弹幕不显示', () {
    expect(visibleDanmaku(items, 0), isEmpty);
  });

  test('1.5 秒时：只显示已出现且在 5 秒窗口内的', () {
    final shown = visibleDanmaku(items, 1.5);
    expect(shown.map((e) => e.text), ['开局留住了我', '搞笑了']);
  });

  test('5 秒时：超过 5 条只留最近 5 条', () {
    final shown = visibleDanmaku(items, 5.0);
    expect(shown.length, 5);
    expect(shown.map((e) => e.text), [
      '搞笑了',
      '第三条',
      '第四条',
      '第五条',
      '第六条',
    ]);
  });

  test('9 秒时：5 秒前的弹幕滑出窗口', () {
    final shown = visibleDanmaku(items, 9.0);
    expect(shown.map((e) => e.text), ['第六条', '后面的']);
  });

  test('暂停冻结：同一位置重复取结果不变', () {
    expect(
      visibleDanmaku(items, 4.5),
      visibleDanmaku(items, 4.5),
    );
  });
}
