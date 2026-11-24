import 'package:flutter_test/flutter_test.dart';
import 'package:vtv_client/api/models.dart';
import 'package:vtv_client/player/vtv_player.dart';
import 'package:vtv_client/ui/responsive.dart';

void main() {
  group('VtvPlayer：mpv 接法（纯函数，不真播）', () {
    test('有 key 时 demuxer-lavf-o 带 decryption_key', () {
      final options = VtvPlayer.buildDemuxerLavfOptions(
        '2174af1cfe63843ced8c4ba281e038a2',
      );
      expect(options, contains('protocol_whitelist=[http,https,tcp,tls,crypto,data,file]'));
      expect(options, contains('decryption_key=2174af1cfe63843ced8c4ba281e038a2'));
    });

    test('无 key 时只有白名单，不带 decryption_key', () {
      expect(
        VtvPlayer.buildDemuxerLavfOptions(null),
        'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
      );
      expect(VtvPlayer.buildDemuxerLavfOptions(''), isNot(contains('decryption_key')));
    });

    test('CDN 请求头：M0 实测的 UA + Referer', () {
      final headers = VtvPlayer.buildCdnHeaders();
      expect(headers['User-Agent'], 'com.dragon.read');
      expect(headers['Referer'], 'https://reading.snssdk.com/');
    });

    test('buildHongguoMedia：地址 + 请求头齐全', () {
      const info = PlayInfo(
        videoUrl: 'https://example.com/v.mp4',
        key: '2174af1cfe63843ced8c4ba281e038a2',
        codec: 'hevc',
        quality: '1080p',
        width: 1080,
        height: 1920,
        duration: 110.969,
        variants: [],
      );
      final media = VtvPlayer.buildHongguoMedia(info);
      expect(media.uri, 'https://example.com/v.mp4');
      expect(media.httpHeaders?['User-Agent'], 'com.dragon.read');
    });
  });

  group('自适应断点（responsive.dart）', () {
    test('screenSizeOf：<600 窄屏，600-900 中屏，>900 宽屏', () {
      expect(screenSizeOf(390), ScreenSize.compact);
      expect(screenSizeOf(599), ScreenSize.compact);
      expect(screenSizeOf(600), ScreenSize.medium);
      expect(screenSizeOf(800), ScreenSize.medium);
      expect(screenSizeOf(900), ScreenSize.expanded);
      expect(screenSizeOf(1920), ScreenSize.expanded);
    });

    test('posterColumns：2 / 3 / 4 / 6 列随宽度变', () {
      expect(posterColumns(320), 2);
      expect(posterColumns(390), 3);
      expect(posterColumns(800), 4);
      expect(posterColumns(1920), 6);
    });

    test('useSideNavigation：宽屏才用左侧导航栏', () {
      expect(useSideNavigation(390), isFalse);
      expect(useSideNavigation(800), isFalse);
      expect(useSideNavigation(1920), isTrue);
    });
  });
}
