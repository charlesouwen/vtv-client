import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/models.dart';
import '../core/config.dart';

/// 播放器错误（中性文案，不暴露内部原因）。
class PlayerException implements Exception {
  const PlayerException(this.userMessage);

  final String userMessage;

  @override
  String toString() => 'PlayerException: $userMessage';
}

/// media_kit（libmpv）封装。
///
/// 红果解密（M0 已验证，ffmpeg 同款 demuxer 测通）：不自己写 AES 解密，
/// 开流前把 playinfo 的 key 交给 mpv 的 ffmpeg 解复用层：
/// `demuxer-lavf-o=protocol_whitelist=[...],decryption_key=<key>`。
/// 每次开流/切流前都必须重设，否则黑屏或无声。
/// 失败时回落到服务端解密直链 /hongguo/stream/{token}（路线 B）。
class VtvPlayer {
  VtvPlayer({Player Function()? playerFactory})
      : _playerFactory = playerFactory ?? Player.new;

  final Player Function() _playerFactory;

  Player? _player;
  VideoController? _controller;
  String? _lastError;

  /// 最近一次打开失败的原因（中性文案），成功打开后清空。
  String? get lastError => _lastError;

  /// 供 Video widget 使用；open 成功后才有值。
  VideoController? get controller => _controller;

  bool get hasPlayer => _player != null;

  /// 拼 demuxer-lavf-o 选项（纯函数，可单元测试）。
  /// 有 key 时带上 decryption_key；无 key 时只留白名单。
  static String buildDemuxerLavfOptions(String? key) {
    const whitelist =
        'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]';
    if (key == null || key.isEmpty) return whitelist;
    return '$whitelist,decryption_key=$key';
  }

  /// 拼红果 CDN 请求的 HTTP 头（纯函数，可单元测试）。
  static Map<String, String> buildCdnHeaders() {
    return <String, String>{
      'User-Agent': kCdnUserAgent,
      'Referer': kCdnReferer,
    };
  }

  /// 拼一次红果开流用的 Media（纯函数，可单元测试）。
  static Media buildHongguoMedia(PlayInfo info) {
    return Media(info.videoUrl, httpHeaders: buildCdnHeaders());
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final created = _playerFactory();
    _player = created;
    _controller = VideoController(created);
    return created;
  }

  Future<void> _setMpvProperties(Player player, PlayInfo info) async {
    final platform = player.platform;
    if (platform == null) return;
    // NativePlayer 才有 setProperty；用 dynamic 调用与 aquan-duanju
    // 的实证接法一致，Web/其他平台没有该方法时跳过。
    final dynamic native = platform;
    try {
      await native.setProperty(
        'demuxer-lavf-o',
        buildDemuxerLavfOptions(info.key),
      );
      await native.setProperty('user-agent', kCdnUserAgent);
      await native.setProperty('referer', kCdnReferer);
      if (Platform.isAndroid) {
        // Android 默认 vo=gpu 在模拟器上建不出 GL 上下文会全黑；
        // mediacodec_embed + hwdec=mediacodec 是实测可用的组合。
        await native.setProperty('vo', 'mediacodec_embed');
        await native.setProperty('hwdec', 'mediacodec');
      }
    } on NoSuchMethodError {
      // 非原生平台没有 setProperty，忽略。
    }
  }

  /// 播红果：playinfo → mpv 解密流式播放。
  /// [fallbackStreamUrl] 是 detail 里服务端签发的 /hongguo/stream 直链，
  /// 主链失败时回落（服务端已解密，不带 key）。
  Future<void> openHongguo(
    PlayInfo info, {
    String? fallbackStreamUrl,
  }) async {
    _lastError = null;
    try {
      final player = _ensurePlayer();
      await _setMpvProperties(player, info);
      await player.open(buildHongguoMedia(info));
    } catch (_) {
      if (fallbackStreamUrl != null && fallbackStreamUrl.isNotEmpty) {
        try {
          final player = _ensurePlayer();
          await player.open(
            Media(fallbackStreamUrl, httpHeaders: buildCdnHeaders()),
          );
          return;
        } catch (_) {
          // 回落也失败，走到下面的统一报错。
        }
      }
      _lastError = '播放失败，请稍后重试';
      throw const PlayerException('播放失败，请稍后重试');
    }
  }

  /// 播采集源直链（m3u8/mp4），mpv 原生支持。
  Future<void> openUrl(String url) async {
    _lastError = null;
    try {
      final player = _ensurePlayer();
      await player.open(Media(url, httpHeaders: buildCdnHeaders()));
    } catch (_) {
      _lastError = '播放失败，请稍后重试';
      throw const PlayerException('播放失败，请稍后重试');
    }
  }

  Future<void> play() async => _player?.play();
  Future<void> pause() async => _player?.pause();

  /// 播放状态流（播放页控制栏/弹幕冻结用）。未 open 前为空流。
  Stream<bool> get playingStream =>
      _player?.stream.playing ?? const Stream<bool>.empty();

  /// 当前播放位置流（进度条/弹幕时间轴用）。未 open 前为空流。
  Stream<Duration> get positionStream =>
      _player?.stream.position ?? const Stream<Duration>.empty();

  /// 总时长流。未 open 前为空流。
  Stream<Duration> get durationStream =>
      _player?.stream.duration ?? const Stream<Duration>.empty();

  /// 跳到指定位置（进度条拖动）。
  Future<void> seek(Duration position) async {
    try {
      await _player?.seek(position);
    } catch (_) {
      // 未 open 或平台不支持时忽略，控制栏仍可用。
    }
  }

  /// 倍速（0.5–2.0）。失败时忽略。
  Future<void> setRate(double rate) async {
    try {
      await _player?.setRate(rate);
    } catch (_) {}
  }

  /// 音量（0.0–1.0）。失败时忽略。
  Future<void> setVolume(double volume) async {
    try {
      await _player?.setVolume(volume);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _controller = null;
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
