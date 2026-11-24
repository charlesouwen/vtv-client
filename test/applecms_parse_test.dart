import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/models.dart';

void main() {
  group('parseVodPlayUrl：\$\$\$ 分组、# 分集、\$ 分标题与地址', () {
    test('单组多集', () {
      final groups = parseVodPlayUrl(
        '第01集\$https://a.com/1.m3u8#第02集\$https://a.com/2.m3u8',
      );
      expect(groups.length, 1);
      expect(groups.first.name, '线路1');
      expect(groups.first.episodes.length, 2);
      expect(groups.first.episodes[0].title, '第01集');
      expect(groups.first.episodes[0].url, 'https://a.com/1.m3u8');
      expect(groups.first.episodes[1].title, '第02集');
    });

    test('多组（\$\$\$ 分隔）', () {
      final groups = parseVodPlayUrl(
        '第01集\$https://a.com/1.m3u8#第02集\$https://a.com/2.m3u8'
        '\$\$\$第01集\$https://b.com/1.mp4',
      );
      expect(groups.length, 2);
      expect(groups[0].name, '线路1');
      expect(groups[1].name, '线路2');
      expect(groups[1].episodes.first.url, 'https://b.com/1.mp4');
    });

    test('空串与脏数据不崩', () {
      expect(parseVodPlayUrl(''), isEmpty);
      expect(parseVodPlayUrl('   '), isEmpty);
      // 没有 $ 分隔的段被跳过，不产生空集。
      final groups = parseVodPlayUrl('第01集\$https://a.com/1.m3u8#坏数据');
      expect(groups.length, 1);
      expect(groups.first.episodes.length, 1);
      // 空组被跳过。
      expect(parseVodPlayUrl('\$\$\$第01集\$https://a.com/1.m3u8').length, 1);
    });

    test('标题含空格会被 trim，地址保留', () {
      final groups = parseVodPlayUrl(
        ' 第01集 \$ https://a.com/1.m3u8 ',
      );
      expect(groups.first.episodes.first.title, '第01集');
      expect(groups.first.episodes.first.url, 'https://a.com/1.m3u8');
    });
  });

  group('VodItem.normalizeTitle', () {
    test('去空白/标点/大小写', () {
      expect(
        VodItem.normalizeTitle('我李长生重回八零，赶山狩猎养妻女'),
        '我李长生重回八零赶山狩猎养妻女',
      );
      expect(VodItem.normalizeTitle(' Reborn 1988 '), 'reborn1988');
      expect(VodItem.normalizeTitle('重生1988，从做倒爷开始起家'), '重生1988从做倒爷开始起家');
    });
  });
}
