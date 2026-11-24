import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../api/repository.dart';
import '../core/config.dart';
import 'player_page.dart';
import 'responsive.dart';
import 'vod_card.dart';

/// 详情页：海报 + 标题 + 简介 + 年份/地区/导演/演员；
/// 源列表（红果 + ikun，短剧里红果排前）；选集网格；
/// 点某集调 playinfo 播；“相关推荐”区（同类型，失败就隐藏）。
///
/// 布局随宽度变：宽屏海报与信息左右排，窄屏上下排。
/// 红果分集标题用 episodeNumber（“第N集”）；采集源分集用
/// playGroups 的分组/分集标题。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item, required this.repository});

  final VodItem item;
  final VtvRepository repository;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<DetailResult> _future;
  late Future<List<VodItem>> _relatedFuture;

  /// 当前选中的源代号（'hongguo' 或采集源代号）。
  String? _selectedSource;

  /// 用户是否手动选过源；手动选过后测速结果不再自动切源。
  bool _userPickedSource = false;

  /// 测速进行中（详情加载完成后在后台测各源首集直连）。
  bool _speedTesting = false;

  /// 测速胜出的源代号（null = 没测出结果）；源列表里打“最快”标记。
  String? _fastestSource;

  /// 采集源当前选中的播放组下标。
  int _cmsGroupIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.detail(widget.item);
    _relatedFuture = widget.repository.related(widget.item);
    // 详情拿到后在后台测速：取用户网络上最快且可直连的源自动切过去；
    // 红果也参与测速，但不是默认首选——测速没出结果前按源列表顺序。
    _future.then((result) => _runSpeedTest(result), onError: (_) {});
  }

  Future<void> _runSpeedTest(DetailResult result) async {
    if (!mounted) return;
    setState(() => _speedTesting = true);
    try {
      final fastest = await widget.repository.pickFastestSource(result);
      if (!mounted) return;
      setState(() {
        _speedTesting = false;
        _fastestSource = fastest;
        // 用户没手动选过源时，测速胜出源自动成为当前源。
        if (fastest != null && !_userPickedSource) {
          _selectedSource = fastest;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _speedTesting = false);
    }
  }

  /// 源列表（按 VTV 规则排序）：短剧红果在前，其余采集源在前。
  List<({String code, String name, bool isHongguo})> _sourceOptions(
    DetailResult result,
  ) {
    final options = <({String code, String name, bool isHongguo})>[];
    if (result.hongguoSeries != null) {
      options.add((code: 'hongguo', name: '红果短剧', isHongguo: true));
    }
    for (final entry in result.cmsItems.entries) {
      options.add((
        code: entry.key,
        name: entry.value.sources.isNotEmpty
            ? entry.value.sources.first.name
            : entry.key,
        isHongguo: false,
      ));
    }
    final shortDrama =
        widget.item.typeName == '短剧' || widget.item.isHongguoPrimary;
    options.sort((a, b) {
      if (shortDrama) {
        if (a.isHongguo != b.isHongguo) return a.isHongguo ? -1 : 1;
      } else {
        if (a.isHongguo != b.isHongguo) return a.isHongguo ? 1 : -1;
      }
      return 0;
    });
    return options;
  }

  void _openHongguoEpisode(
    DetailResult result,
    HongguoSeries series,
    HongguoEpisode episode,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          repository: widget.repository,
          series: series,
          episode: episode,
          detail: result,
        ),
      ),
    );
  }

  void _openCmsEpisode(
    DetailResult result,
    VodItem cmsItem,
    CmsEpisode episode,
    int groupIndex,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage.cms(
          repository: widget.repository,
          cmsItem: cmsItem,
          cmsEpisode: episode,
          cmsGroupIndex: groupIndex,
          detail: result,
        ),
      ),
    );
  }

  void _openDetail(VodItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(item: item, repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: FutureBuilder<DetailResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('内容暂时获取失败，请稍后重试'));
          }
          final result = snapshot.data!;
          final options = _sourceOptions(result);
          if (options.isEmpty) {
            return const Center(child: Text('该影片暂无可播来源'));
          }
          _selectedSource ??= options.first.code;
          final selected = options.firstWhere(
            (o) => o.code == _selectedSource,
            orElse: () => options.first,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= kExpandedBreakpoint;
              final body = _DetailBody(
                item: widget.item,
                result: result,
                selected: selected,
                options: options,
                cmsGroupIndex: _cmsGroupIndex,
                speedTesting: _speedTesting,
                fastestSource: _fastestSource,
                onSelectSource: (code) => setState(() {
                  _selectedSource = code;
                  _userPickedSource = true;
                  _cmsGroupIndex = 0;
                }),
                onSelectCmsGroup: (i) =>
                    setState(() => _cmsGroupIndex = i),
                onSelectHongguoEpisode: (e) => _openHongguoEpisode(
                  result,
                  result.hongguoSeries!,
                  e,
                ),
                onSelectCmsEpisode: (item, episode, groupIndex) =>
                    _openCmsEpisode(result, item, episode, groupIndex),
                relatedFuture: _relatedFuture,
                onSelectRelated: _openDetail,
                episodeColumns:
                    wide ? 8 : (constraints.maxWidth >= 600 ? 6 : 4),
              );
              if (!wide) {
                return CenteredContent(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: body,
                  ),
                );
              }
              return CenteredContent(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: body,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.item,
    required this.result,
    required this.selected,
    required this.options,
    required this.cmsGroupIndex,
    required this.speedTesting,
    required this.fastestSource,
    required this.onSelectSource,
    required this.onSelectCmsGroup,
    required this.onSelectHongguoEpisode,
    required this.onSelectCmsEpisode,
    required this.relatedFuture,
    required this.onSelectRelated,
    required this.episodeColumns,
  });

  final VodItem item;
  final DetailResult result;
  final ({String code, String name, bool isHongguo}) selected;
  final List<({String code, String name, bool isHongguo})> options;
  final int cmsGroupIndex;

  /// 测速进行中（详情加载后在后台测各源首集直连）。
  final bool speedTesting;

  /// 测速胜出的源代号（null = 没测出结果）；源列表里打“最快”标记。
  final String? fastestSource;
  final ValueChanged<String> onSelectSource;
  final ValueChanged<int> onSelectCmsGroup;
  final ValueChanged<HongguoEpisode> onSelectHongguoEpisode;
  final void Function(VodItem cmsItem, CmsEpisode episode, int groupIndex)
      onSelectCmsEpisode;
  final Future<List<VodItem>> relatedFuture;
  final ValueChanged<VodItem> onSelectRelated;
  final int episodeColumns;

  @override
  Widget build(BuildContext context) {
    final series = result.hongguoSeries;
    final cmsItem = selected.isHongguo ? null : result.cmsItems[selected.code];
    // 简介/导演/演员：选中源的详情优先，没有就用卡片自带的信息。
    final content = selected.isHongguo
        ? (series?.content ?? '')
        : (cmsItem?.content ?? item.content);
    final director = selected.isHongguo ? '' : (cmsItem?.director ?? '');
    final actor = selected.isHongguo ? '' : (cmsItem?.actor ?? '');
    final remarks = selected.isHongguo
        ? (series?.remarks ?? item.remarks)
        : (cmsItem?.remarks ?? item.remarks);
    final year = item.year.isNotEmpty
        ? item.year
        : (cmsItem?.year ?? '');
    final area = item.area.isNotEmpty
        ? item.area
        : (cmsItem?.area ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(
              pic: series?.pic ?? cmsItem?.pic ?? item.pic,
              width: 160,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  _metaLine([year, area, item.typeName, remarks]),
                  if (director.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _metaLine(['导演', director]),
                  ],
                  if (actor.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '演员：$actor',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (series?.playbackUnavailable == true) ...[
          const SizedBox(height: 8),
          const Text('该剧暂不可播（片源编码原因）'),
        ],
        if (content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 16),
        Text('播放源', style: Theme.of(context).textTheme.titleMedium),
        if (speedTesting) ...[
          const SizedBox(height: 4),
          const Text('正在测速…', style: TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 8),
        Wrap(
          key: const Key('source-list'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                key: Key('source-${option.code}'),
                label: Text(
                  option.code == fastestSource
                      ? '${option.name} · 最快'
                      : option.name,
                ),
                selected: selected.code == option.code,
                onSelected: (value) {
                  if (value) onSelectSource(option.code);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (selected.isHongguo && series != null)
          _HongguoEpisodes(
            series: series,
            episodeColumns: episodeColumns,
            onSelectEpisode: onSelectHongguoEpisode,
          )
        else if (cmsItem != null)
          _CmsEpisodes(
            cmsItem: cmsItem,
            groupIndex: cmsGroupIndex,
            episodeColumns: episodeColumns,
            onSelectGroup: onSelectCmsGroup,
            onSelectEpisode: (episode) =>
                onSelectCmsEpisode(cmsItem, episode, cmsGroupIndex),
          ),
        const SizedBox(height: 24),
        FutureBuilder<List<VodItem>>(
          future: relatedFuture,
          builder: (context, snapshot) {
            // 相关推荐失败或为空时隐藏该区，不显示空区。
            final related = snapshot.data ?? const <VodItem>[];
            if (snapshot.connectionState == ConnectionState.waiting ||
                related.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              key: const Key('related-section'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '相关推荐',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                VodCardGrid(items: related, onSelect: onSelectRelated),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _metaLine(List<String> parts) {
    final shown = parts.where((p) => p.isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Text(shown.join(' · '));
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.pic, required this.width});

  final String pic;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        displayPosterUrl(pic),
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: width * 1.33,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.movie_outlined, size: 48),
        ),
      ),
    );
  }
}

class _HongguoEpisodes extends StatelessWidget {
  const _HongguoEpisodes({
    required this.series,
    required this.episodeColumns,
    required this.onSelectEpisode,
  });

  final HongguoSeries series;
  final int episodeColumns;
  final ValueChanged<HongguoEpisode> onSelectEpisode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选集（${series.episodes.length}集）',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        GridView.builder(
          key: const Key('episode-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: episodeColumns,
            childAspectRatio: 2.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: series.episodes.length,
          itemBuilder: (context, index) {
            final episode = series.episodes[index];
            return DpadFocusable(
              autofocus: index == 0,
              onSelect: () => onSelectEpisode(episode),
              child: OutlinedButton(
                key: ValueKey('episode-${episode.episodeNumber}'),
                onPressed: () => onSelectEpisode(episode),
                child: Text(
                  '第${episode.episodeNumber}集',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CmsEpisodes extends StatelessWidget {
  const _CmsEpisodes({
    required this.cmsItem,
    required this.groupIndex,
    required this.episodeColumns,
    required this.onSelectGroup,
    required this.onSelectEpisode,
  });

  final VodItem cmsItem;
  final int groupIndex;
  final int episodeColumns;
  final ValueChanged<int> onSelectGroup;
  final ValueChanged<CmsEpisode> onSelectEpisode;

  @override
  Widget build(BuildContext context) {
    final groups = cmsItem.playGroups;
    if (groups.isEmpty) {
      return const Text('该来源暂无分集');
    }
    final safeIndex = groupIndex.clamp(0, groups.length - 1);
    final episodes = groups[safeIndex].episodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < groups.length; i++)
                ChoiceChip(
                  key: Key('cms-group-$i'),
                  label: Text(groups[i].name),
                  selected: safeIndex == i,
                  onSelected: (value) {
                    if (value) onSelectGroup(i);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '选集（${episodes.length}集）',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        GridView.builder(
          key: const Key('episode-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: episodeColumns,
            childAspectRatio: 2.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            return DpadFocusable(
              autofocus: index == 0,
              onSelect: () => onSelectEpisode(episode),
              child: OutlinedButton(
                key: ValueKey('episode-cms-$index'),
                onPressed: () => onSelectEpisode(episode),
                child: Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
