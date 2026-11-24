import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/repository.dart';
import '../core/prefs.dart';
import '../player/vtv_player.dart';
import 'responsive.dart';

/// 播放页：media_kit Video + 控制栏（播放/暂停、进度条、倍速、音量、
/// 全屏）；红果走 playinfo + decryption_key（VtvPlayer 已接好）；
/// 弹幕仅展示（hongguo.danmaku，按播放时间渲染，暂停冻结，不发送）；
/// 选集列表（点集切换，播完前 0.5 秒自动切下一集）；源切换
/// （详情页选的源 + 播放页内可换源）；竖屏短剧按 playinfo 宽高分流
/// （竖屏保弹幕、横屏全屏，沿用网页端规则）；音量/倍速/弹幕开关
/// 存 SharedPreferences。
///
/// 两种入口：红果（series + episode）与采集源直链（cmsItem + episode）。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.repository,
    required this.series,
    required this.episode,
    this.detail,
  })  : cmsItem = null,
        cmsEpisode = null,
        cmsGroupIndex = 0;

  const PlayerPage.cms({
    super.key,
    required this.repository,
    required this.cmsItem,
    required this.cmsEpisode,
    required this.cmsGroupIndex,
    this.detail,
  })  : series = null,
        episode = null;

  final VtvRepository repository;
  final HongguoSeries? series;
  final HongguoEpisode? episode;
  final VodItem? cmsItem;
  final CmsEpisode? cmsEpisode;
  final int cmsGroupIndex;
  final DetailResult? detail;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _rates = [0.5, 1.0, 1.5, 2.0];

  final VtvPlayer _player = VtvPlayer();
  SharedPreferences? _prefs;

  String _sourceCode = 'hongguo';
  HongguoEpisode? _hgEpisode;
  VodItem? _cmsItem;
  CmsEpisode? _cmsEpisode;
  int _cmsGroupIndex = 0;

  PlayInfo? _playInfo;
  List<DanmakuItem> _danmaku = [];
  String? _error;
  bool _loading = true;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  double _rate = 1.0;
  bool _danmakuEnabled = true;
  bool _isFullscreen = false;

  /// 本集已触发过自动切集（防重复触发）。
  bool _autoAdvanced = false;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  bool get _isHongguoSource => _sourceCode == 'hongguo';

  String get _title {
    if (_isHongguoSource) {
      final series = widget.series;
      final episode = _hgEpisode;
      if (series != null && episode != null) {
        return '${series.title} 第${episode.episodeNumber}集';
      }
      return widget.series?.title ?? '';
    }
    final item = _cmsItem;
    final episode = _cmsEpisode;
    if (item != null && episode != null) {
      return '${item.title} ${episode.title}';
    }
    return _cmsItem?.title ?? '';
  }

  @override
  void initState() {
    super.initState();
    _sourceCode = widget.series != null ? 'hongguo' : (widget.cmsItem?.source ?? 'ikun');
    _hgEpisode = widget.episode;
    _cmsItem = widget.cmsItem;
    _cmsEpisode = widget.cmsEpisode;
    _cmsGroupIndex = widget.cmsGroupIndex;
    _loadPrefs();
    _playCurrent();
  }

  Future<void> _loadPrefs() async {
    final prefs = await loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _volume = readDoublePref(prefs, kPrefVolume, 1.0).clamp(0.0, 1.0);
      _rate = readDoublePref(prefs, kPrefRate, 1.0);
      if (!_rates.contains(_rate)) _rate = 1.0;
      _danmakuEnabled = readBoolPref(prefs, kPrefDanmakuEnabled, true);
    });
    await _player.setVolume(_volume);
    await _player.setRate(_rate);
  }

  void _subscribeStreams() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub = _player.playingStream.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      _maybeAutoAdvance();
    });
  }

  /// 播完前 0.5 秒自动切下一集（同源内；跨季续播是后续接口，这里留空）。
  void _maybeAutoAdvance() {
    if (_autoAdvanced) return;
    if (_duration.inMilliseconds <= 0) return;
    final remaining = _duration - _position;
    if (remaining <= const Duration(milliseconds: 500)) {
      if (_hasNextEpisode()) {
        _autoAdvanced = true;
        _playNext();
      }
    }
  }

  bool _hasNextEpisode() => _nextEpisode() != null;

  /// 下一集（同源内）：红果按 episodeNumber 递增；采集源按当前组内顺序。
  ({HongguoEpisode? hg, CmsEpisode? cms})? _nextEpisode() {
    if (_isHongguoSource) {
      final series = widget.series;
      final current = _hgEpisode;
      if (series == null || current == null) return null;
      final next = series.episodes
          .where((e) => e.episodeNumber == current.episodeNumber + 1)
          .firstOrNull;
      if (next == null) return null;
      return (hg: next, cms: null);
    }
    final item = _cmsItem;
    if (item == null || item.playGroups.isEmpty) return null;
    final group = item.playGroups[_cmsGroupIndex.clamp(0, item.playGroups.length - 1)];
    final index = group.episodes.indexOf(_cmsEpisode!);
    if (index < 0 || index + 1 >= group.episodes.length) return null;
    return (hg: null, cms: group.episodes[index + 1]);
  }

  void _playNext() {
    final next = _nextEpisode();
    if (next == null) return;
    setState(() {
      if (next.hg != null) _hgEpisode = next.hg;
      if (next.cms != null) _cmsEpisode = next.cms;
      _autoAdvanced = false;
    });
    _playCurrent();
  }

  Future<void> _playCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _autoAdvanced = false;
    });
    try {
      if (_isHongguoSource) {
        final series = widget.series!;
        final episode = _hgEpisode!;
        final info = await widget.repository.hongguo.playinfo(
          seriesId: series.id,
          episodeIndex: episode.playIndex,
        );
        if (!mounted) return;
        setState(() => _playInfo = info);
        // 弹幕失败就当没有，不影响播放。
        try {
          final danmaku = await widget.repository.hongguo.danmaku(
            seriesId: series.id,
            episodeIndex: episode.playIndex,
          );
          if (mounted) setState(() => _danmaku = danmaku);
        } catch (_) {
          if (mounted) setState(() => _danmaku = const []);
        }
        await _player.openHongguo(
          info,
          fallbackStreamUrl: episode.streamUrl,
        );
      } else {
        final episode = _cmsEpisode;
        if (episode == null) throw const PlayerException('播放失败，请稍后重试');
        setState(() => _playInfo = null);
        await _player.openUrl(episode.url);
      }
      if (!mounted) return;
      await _player.setVolume(_volume);
      await _player.setRate(_rate);
      _subscribeStreams();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PlayerException
            ? e.userMessage
            : '内容暂时获取失败，请稍后重试';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 换源：同集号优先对齐（红果第 N 集 ↔ 采集源第 N 集），没有就播第 1 集。
  /// 目标源无分集时不切换（保持当前源继续播）。
  void _switchSource(String code) {
    if (code == _sourceCode) return;
    final detail = widget.detail;
    if (detail == null) return;
    if (code == 'hongguo') {
      final series = detail.hongguoSeries;
      if (series == null || series.episodes.isEmpty) return;
      final currentNumber = _cmsEpisodeNumber();
      final target = series.episodes
              .where((e) => e.episodeNumber == currentNumber)
              .firstOrNull ??
          series.episodes.first;
      setState(() {
        _sourceCode = code;
        _hgEpisode = target;
      });
    } else {
      final cmsItem = detail.cmsItems[code];
      if (cmsItem == null || cmsItem.playGroups.isEmpty) return;
      final currentNumber = _hgEpisode?.episodeNumber ?? 1;
      final group = cmsItem.playGroups.first;
      final target = group.episodes.length >= currentNumber
          ? group.episodes[currentNumber - 1]
          : group.episodes.first;
      setState(() {
        _sourceCode = code;
        _cmsItem = cmsItem;
        _cmsEpisode = target;
        _cmsGroupIndex = 0;
      });
    }
    _playCurrent();
  }

  /// 从采集源分集标题里解析集号（“第N集”/“N”），解析不到返回 1。
  int _cmsEpisodeNumber() {
    final title = _cmsEpisode?.title ?? '';
    final match = RegExp(r'(\d+)').firstMatch(title);
    return int.tryParse(match?.group(1) ?? '') ?? 1;
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play();
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _cycleRate() async {
    final index = _rates.indexOf(_rate);
    final next = _rates[(index + 1) % _rates.length];
    setState(() => _rate = next);
    await _player.setRate(next);
    await writeDoublePref(_prefs, kPrefRate, next);
  }

  Future<void> _toggleDanmaku() async {
    final next = !_danmakuEnabled;
    setState(() => _danmakuEnabled = next);
    await writeBoolPref(_prefs, kPrefDanmakuEnabled, next);
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _player.controller;
    final isVertical = _playInfo?.isVertical ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(_title),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kExpandedBreakpoint;
          return Column(
            children: [
              Expanded(
                flex: _isFullscreen ? 10 : 5,
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : _error != null && controller == null
                              ? _ErrorView(
                                  message: _error!,
                                  onRetry: _playCurrent,
                                )
                              : controller != null
                                  ? _VideoArea(
                                      controller: controller,
                                      isVertical: isVertical,
                                      danmaku: _danmakuEnabled
                                          ? _danmaku
                                          : const <DanmakuItem>[],
                                      position: _position,
                                    )
                                  : const Text(
                                      '播放器初始化失败',
                                      style: TextStyle(color: Colors.white),
                                    ),
                ),
              ),
              _ControlBar(
                wide: wide,
                playInfo: _playInfo,
                isPlaying: _playing,
                position: _position,
                duration: _duration,
                rate: _rate,
                volume: _volume,
                danmakuEnabled: _danmakuEnabled,
                isFullscreen: _isFullscreen,
                isVertical: isVertical,
                onTogglePlay: _togglePlay,
                onSeek: (position) => _player.seek(position),
                onCycleRate: _cycleRate,
                onVolumeChanged: (value) async {
                  setState(() => _volume = value);
                  await _player.setVolume(value);
                  await writeDoublePref(_prefs, kPrefVolume, value);
                },
                onToggleDanmaku: _toggleDanmaku,
                onToggleFullscreen: () =>
                    setState(() => _isFullscreen = !_isFullscreen),
                error: _error,
              ),
              if (!_isFullscreen) ...[
                if (widget.detail != null) _SourceSwitcher(
                  detail: widget.detail!,
                  currentCode: _sourceCode,
                  onSwitch: _switchSource,
                ),
                Expanded(
                  flex: 4,
                  child: _EpisodeList(
                    isHongguo: _isHongguoSource,
                    series: widget.series,
                    currentHgEpisode: _hgEpisode,
                    cmsItem: _cmsItem,
                    cmsGroupIndex: _cmsGroupIndex,
                    currentCmsEpisode: _cmsEpisode,
                    onSelectHgEpisode: (episode) {
                      setState(() => _hgEpisode = episode);
                      _playCurrent();
                    },
                    onSelectCmsEpisode: (episode) {
                      setState(() => _cmsEpisode = episode);
                      _playCurrent();
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 视频区：竖屏短剧按宽高比居中（上下留黑边，弹幕只画在画面内）；
/// 横屏填满。弹幕层按播放时间渲染，暂停时位置流停住、弹幕冻结。
class _VideoArea extends StatelessWidget {
  const _VideoArea({
    required this.controller,
    required this.isVertical,
    required this.danmaku,
    required this.position,
  });

  final VideoController controller;
  final bool isVertical;
  final List<DanmakuItem> danmaku;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final video = Video(controller: controller);
    final withDanmaku = Stack(
      alignment: Alignment.topCenter,
      children: [
        video,
        if (danmaku.isNotEmpty)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _DanmakuOverlay(items: danmaku, position: position),
          ),
      ],
    );
    if (!isVertical) return withDanmaku;
    return AspectRatio(aspectRatio: 9 / 16, child: withDanmaku);
  }
}

/// 弹幕可见窗口（纯函数，便于测试）：当前播放时间前后 5 秒内的弹幕，
/// 最多 5 条。位置来自播放器 position 流——暂停时 position 不动，
/// 弹幕冻结；倍速/拖动时 position 跳变，弹幕立即对齐。
List<DanmakuItem> visibleDanmaku(
  List<DanmakuItem> items,
  double nowSeconds, {
  double windowSeconds = 5,
  int maxCount = 5,
}) {
  final visible = items
      .where(
        (item) => item.time <= nowSeconds && item.time > nowSeconds - windowSeconds,
      )
      .toList();
  if (visible.length <= maxCount) return visible;
  return visible.sublist(visible.length - maxCount);
}

/// 弹幕层：只展示当前播放时间前后 5 秒内的弹幕（最多 5 条），
class _DanmakuOverlay extends StatelessWidget {
  const _DanmakuOverlay({required this.items, required this.position});

  final List<DanmakuItem> items;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final now = position.inMilliseconds / 1000.0;
    final shown = visibleDanmaku(items, now);
    return Column(
      key: const Key('danmaku-overlay'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in shown)
          Text(
            item.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 2,
                  offset: Offset(1, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.wide,
    required this.playInfo,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.rate,
    required this.volume,
    required this.danmakuEnabled,
    required this.isFullscreen,
    required this.isVertical,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onCycleRate,
    required this.onVolumeChanged,
    required this.onToggleDanmaku,
    required this.onToggleFullscreen,
    required this.error,
  });

  final bool wide;
  final PlayInfo? playInfo;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double rate;
  final double volume;
  final bool danmakuEnabled;
  final bool isFullscreen;
  final bool isVertical;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onCycleRate;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onToggleFullscreen;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds.clamp(0, totalMs);
    final qualityChip = playInfo == null
        ? const SizedBox.shrink()
        : Container(
            key: const Key('playinfo-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${playInfo!.quality} · ${playInfo!.codec}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          );
    final orientationChip = playInfo == null
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isVertical ? '竖屏' : '横屏',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          );
    return Container(
      key: const Key('player-controls'),
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('play-pause-button'),
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: onTogglePlay,
              ),
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: const Key('seek-slider'),
                  value: totalMs > 0 ? positionMs / totalMs : 0,
                  onChanged: totalMs > 0
                      ? (value) => onSeek(
                            Duration(
                              milliseconds: (value * totalMs).round(),
                            ),
                          )
                      : null,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Row(
            children: [
              TextButton(
                key: const Key('speed-button'),
                onPressed: onCycleRate,
                child: Text(
                  '${rate}x',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                    Expanded(
                      child: Slider(
                        key: const Key('volume-slider'),
                        value: volume,
                        onChanged: onVolumeChanged,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('danmaku-toggle'),
                icon: Icon(
                  danmakuEnabled
                      ? Icons.closed_caption
                      : Icons.closed_caption_off,
                  color: Colors.white,
                ),
                onPressed: onToggleDanmaku,
              ),
              IconButton(
                key: const Key('fullscreen-button'),
                icon: Icon(
                  isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: onToggleFullscreen,
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 12),
              if (error != null)
                Flexible(
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Flexible(
                  child: Text(
                    isPlaying ? '正在播放' : '已暂停',
                    style: const TextStyle(color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              orientationChip,
              const SizedBox(width: 8),
              qualityChip,
            ],
          ),
        ],
      ),
    );
  }
}

/// 播放页内换源（详情页选的源 + 播放页内可换源）。
class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({
    required this.detail,
    required this.currentCode,
    required this.onSwitch,
  });

  final DetailResult detail;
  final String currentCode;
  final ValueChanged<String> onSwitch;

  @override
  Widget build(BuildContext context) {
    final options = <({String code, String name})>[];
    if (detail.hongguoSeries != null) {
      options.add((code: 'hongguo', name: '红果短剧'));
    }
    for (final entry in detail.cmsItems.entries) {
      options.add((
        code: entry.key,
        name: entry.value.sources.isNotEmpty
            ? entry.value.sources.first.name
            : entry.key,
      ));
    }
    if (options.length < 2) return const SizedBox.shrink();
    return Container(
      key: const Key('player-source-list'),
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: [
          for (final option in options)
            ChoiceChip(
              key: Key('player-source-${option.code}'),
              label: Text(
                option.name,
                style: const TextStyle(color: Colors.white),
              ),
              selected: currentCode == option.code,
              selectedColor: Colors.white24,
              onSelected: (value) {
                if (value) onSwitch(option.code);
              },
            ),
        ],
      ),
    );
  }
}

/// 选集列表（点集切换）。红果按 episodeNumber，采集源按当前组分集。
class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.isHongguo,
    required this.series,
    required this.currentHgEpisode,
    required this.cmsItem,
    required this.cmsGroupIndex,
    required this.currentCmsEpisode,
    required this.onSelectHgEpisode,
    required this.onSelectCmsEpisode,
  });

  final bool isHongguo;
  final HongguoSeries? series;
  final HongguoEpisode? currentHgEpisode;
  final VodItem? cmsItem;
  final int cmsGroupIndex;
  final CmsEpisode? currentCmsEpisode;
  final ValueChanged<HongguoEpisode> onSelectHgEpisode;
  final ValueChanged<CmsEpisode> onSelectCmsEpisode;

  @override
  Widget build(BuildContext context) {
    final hgEpisodes = series?.episodes ?? const <HongguoEpisode>[];
    final cmsEpisodes = cmsItem == null || cmsItem!.playGroups.isEmpty
        ? const <CmsEpisode>[]
        : cmsItem!
            .playGroups[cmsGroupIndex.clamp(0, cmsItem!.playGroups.length - 1)]
            .episodes;
    final count = isHongguo ? hgEpisodes.length : cmsEpisodes.length;
    return Container(
      key: const Key('player-episode-list'),
      color: Colors.black,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选集（$count集）',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 2.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                if (isHongguo) {
                  final episode = hgEpisodes[index];
                  final selected =
                      episode.episodeNumber ==
                          currentHgEpisode?.episodeNumber;
                  return OutlinedButton(
                    key: ValueKey('player-episode-${episode.episodeNumber}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor:
                          selected ? Colors.white24 : Colors.transparent,
                    ),
                    onPressed: () => onSelectHgEpisode(episode),
                    child: Text(
                      '第${episode.episodeNumber}集',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                final episode = cmsEpisodes[index];
                final selected = episode.title == currentCmsEpisode?.title;
                return OutlinedButton(
                  key: ValueKey('player-episode-cms-$index'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor:
                        selected ? Colors.white24 : Colors.transparent,
                  ),
                  onPressed: () => onSelectCmsEpisode(episode),
                  child: Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
