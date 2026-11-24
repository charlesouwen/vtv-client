import '../core/http_client.dart';
import 'applecms.dart';
import 'category_map.dart';
import 'cms_sources.dart';
import 'hongguo.dart';
import 'models.dart';

/// 详情聚合结果：一影片多源。
class DetailResult {
  const DetailResult({
    required this.item,
    this.hongguoSeries,
    this.cmsItems = const <String, VodItem>{},
    this.detailMs = const <String, int>{},
  });

  /// 统一卡片。
  final VodItem item;

  /// 红果详情（含分集与 streamUrl），无红果源时为 null。
  final HongguoSeries? hongguoSeries;

  /// 采集源详情，按来源代号索引（VodItem.playGroups 里有分集）。
  final Map<String, VodItem> cmsItems;

  /// 各源详情接口耗时（毫秒），选源测速的回落依据；
  /// 直连都失败时按它取最快（走直链播，不走代理——原生无 CORS）。
  final Map<String, int> detailMs;
}

/// 一次源测速探针结果（纯数据，选源逻辑见 [VtvRepository.selectFastest]）。
class SourceProbe {
  const SourceProbe({
    required this.code,
    required this.ms,
    required this.direct,
  });

  /// 来源代号（'hongguo' 或采集源代号）。
  final String code;

  /// 首集直连耗时（毫秒）；直连失败时为详情耗时或 -1。
  final int ms;

  /// 首集是否可直连（m3u8 读到 #EXTM3U，或 mp4 HEAD 200）。
  final bool direct;
}

/// 统一数据仓库：搜索聚合、推荐、详情聚合。
///
/// 搜索质量线（与网页端 hg1 一致）：
/// - 按影片分组去重，同名只留一卡；
/// - 红果条目做主键（有红果来源的卡，主键就是红果）；
/// - 同等相关性下红果组在前；
/// - 标题与关键词零重叠的结果去掉。
///
/// 多源规则（M1 补采集源）：
/// - 18 个 AppleCMS 源全接（注册表见 lib/api/cms_sources.dart），
///   默认 ikun；首页电影/电视剧/综艺/动漫走采集源，短剧走红果主力；
/// - 推荐/搜索并行拉全部源，失败的源静默跳过，不阻塞其他源；
/// - 详情按来源代号路由到对应源的 detail；
/// - 选源：详情页加载后测速，取用户网络上最快且可直连的源；
///   红果也参与测速，但不是默认首选——测速没出结果前按源列表
///   顺序（短剧红果在前，其余采集源在前）。
/// - 红果逻辑不动：仍走自家 EdgeOne /hongguo/*，不直调红果。
class VtvRepository {
  VtvRepository({
    HongguoApi? hongguo,
    AppleCmsApi? appleCms,
    List<AppleCmsApi>? cmsApis,
    VtvHttpClient? httpClient,
  }) {
    // 共享一个 HTTP 客户端：显式传入的优先，其次用显式传入的
    // ikun 实例的客户端（测试里是同一个假客户端），否则新建。
    // 这样多源池里的 18 个源共用一个客户端，测试可注入假的。
    _httpClient = httpClient ?? appleCms?.client ?? VtvHttpClient();
    _hongguo = hongguo ?? HongguoApi(client: _httpClient);
    if (cmsApis != null) {
      _cmsApis = {for (final a in cmsApis) a.sourceCode: a};
    } else {
      _cmsApis = {
        for (final s in kCmsSources)
          s.code: AppleCmsApi(
            client: _httpClient,
            apiBase: s.apiBase,
            sourceCode: s.code,
            sourceName: s.name,
          ),
      };
    }
    // 显式传入的 ikun 实例覆盖池子里的默认 ikun。
    if (appleCms != null) _cmsApis['ikun'] = appleCms;
  }

  late final VtvHttpClient _httpClient;
  late final HongguoApi _hongguo;
  late final Map<String, AppleCmsApi> _cmsApis;

  HongguoApi get hongguo => _hongguo;

  /// 默认采集源（ikun）。
  AppleCmsApi get appleCms => _cmsApis['ikun']!;

  /// 全部采集源实例（按注册表顺序）。
  List<AppleCmsApi> get cmsApis =>
      kCmsSources.map((s) => _cmsApis[s.code]!).toList();

  /// 短剧推荐：走红果 recommend（红果是短剧主力）。
  Future<VodListResult> recommendShortDrama({int page = 1}) {
    return _hongguo.recommend(page: page);
  }

  /// 其余分类推荐：18 个采集源并行拉资源榜，合并去重后按最新排。
  /// 单源失败静默跳过；全部失败才抛错。
  Future<VodListResult> recommendByType({int page = 1}) async {
    final futures = cmsApis.map(
      (api) => api
          .list(null, page: page)
          .then<List<VodItem>>((r) => r.items, onError: (_) => const <VodItem>[]),
    );
    final results = await Future.wait(futures);
    final items = groupRecommendResults(
      results.expand((e) => e).toList(),
    );
    if (items.isEmpty) {
      throw ApiException.server('recommend empty');
    }
    return VodListResult(
      items: items,
      total: items.length,
      page: page,
      pageCount: 0,
    );
  }

  /// 推荐合并去重（纯函数，便于单元测试）：
  /// 同名（归一化标题相同）合并为一卡，来源合并；主键取注册表
  /// 顺序最靠前的源（ikun 优先）；按 vod_time 最新在前。
  static List<VodItem> groupRecommendResults(List<VodItem> items) {
    final order = <String, int>{
      for (var i = 0; i < kCmsSources.length; i++) kCmsSources[i].code: i,
    };
    final groups = <String, List<VodItem>>{};
    final keys = <String>[];
    for (final item in items) {
      final key = VodItem.normalizeTitle(item.title);
      if (key.isEmpty) continue;
      if (!groups.containsKey(key)) {
        groups[key] = <VodItem>[];
        keys.add(key);
      }
      groups[key]!.add(item);
    }
    final cards = <VodItem>[];
    for (final key in keys) {
      final group = groups[key]!;
      // 主键：注册表顺序最靠前的源（ikun 第一）。
      group.sort((a, b) {
        final oa = order[a.source] ?? 999;
        final ob = order[b.source] ?? 999;
        return oa.compareTo(ob);
      });
      final primary = group.first;
      final sources = <SourceRef>[];
      for (final item in group) {
        sources.addAll(item.sources);
      }
      // 去重 sources（同源只留一个）。
      final seen = <String>{};
      final uniqueSources = sources.where((s) => seen.add(s.code)).toList();
      // 主键来源排首位。
      uniqueSources.sort((a, b) {
        if (a.code == primary.source && b.code != primary.source) return -1;
        if (b.code == primary.source && a.code != primary.source) return 1;
        return 0;
      });
      // 卡片取主键条目，但补全简介/导演/演员（取组内最全的）。
      var content = primary.content;
      var director = primary.director;
      var actor = primary.actor;
      for (final item in group) {
        if (content.isEmpty) content = item.content;
        if (director.isEmpty) director = item.director;
        if (actor.isEmpty) actor = item.actor;
      }
      cards.add(
        primary.copyWith(
          sources: uniqueSources,
          content: content,
          director: director,
          actor: actor,
        ),
      );
    }
    // 最新在前（vod_time 字符串可直接比较；空时间排最后）。
    cards.sort((a, b) {
      if (a.time.isEmpty && b.time.isEmpty) return 0;
      if (a.time.isEmpty) return 1;
      if (b.time.isEmpty) return -1;
      return b.time.compareTo(a.time);
    });
    return cards;
  }

  /// 分类浏览：ikun / ruyi / bfzy 三源（type_id 实测归一）并行拉，
  /// 合并去重；年份由服务端筛的源才传 year（ikun、bfzy），
  /// 其余源靠调用方客户端过滤（filterCategoryByYear）。
  /// “全部”子类不传 t 参数；某源没有该子类时跳过该源。
  Future<VodListResult> categoryList({
    required SubCategory sub,
    required YearFilter year,
    int page = 1,
  }) async {
    final yearValue = year.serverYear;
    final futures = <Future<List<VodItem>>>[];
    for (final code in kCategorySourceCodes) {
      final api = _cmsApis[code];
      if (api == null) continue;
      // “全部”子类 typeIds 为空：不传 t。
      final typeId = sub.typeIds.isEmpty ? null : sub.typeIdFor(code);
      if (sub.typeIds.isNotEmpty && typeId == null) continue;
      final passYear = kCmsYearSupported.contains(code) ? yearValue : null;
      futures.add(
        api
            .list(typeId, page: page, year: passYear)
            .then<List<VodItem>>((r) => r.items, onError: (_) => const <VodItem>[]),
      );
    }
    final results = await Future.wait(futures);
    final items = groupRecommendResults(
      results.expand((e) => e).toList(),
    );
    if (items.isEmpty) {
      throw ApiException.server('category empty');
    }
    return VodListResult(
      items: items,
      total: items.length,
      page: page,
      pageCount: 0,
    );
  }

  /// 短剧题材浏览：红果 search 为主力，暴风（bfzy）按题材 type_id
  /// 作补充混入（红果在前，暴风去重后追加），不单独成类。
  Future<VodListResult> shortDramaTheme(String theme, {int page = 1}) async {
    final hgFuture = _hongguo
        .search(theme, page: page)
        .then<List<VodItem>>((r) => r.items, onError: (_) => const <VodItem>[]);
    final bfzyTypeId = kShortDramaThemeBfzyTypeId[theme];
    final bfzyFuture = bfzyTypeId == null
        ? Future<List<VodItem>>.value(const <VodItem>[])
        : _cmsApis['bfzy']!
            .list(bfzyTypeId, page: page)
            .then<List<VodItem>>((r) => r.items, onError: (_) => const <VodItem>[]);
    final results = await Future.wait([hgFuture, bfzyFuture]);
    final hgItems = results[0];
    final bfzyItems = results[1];
    // 暴风补充：标题已在红果结果里的去掉，剩下的追加在红果后面。
    final seen = hgItems.map((e) => VodItem.normalizeTitle(e.title)).toSet();
    final merged = <VodItem>[...hgItems];
    for (final item in bfzyItems) {
      if (seen.add(VodItem.normalizeTitle(item.title))) merged.add(item);
    }
    if (merged.isEmpty) {
      throw ApiException.server('short drama theme empty');
    }
    return VodListResult(
      items: merged,
      total: merged.length,
      page: page,
      pageCount: 0,
    );
  }

  /// 相关推荐：同类型内容，失败返回空（调用方隐藏该区，不显示空区）。
  /// 短剧走红果推荐，其余走采集源资源榜；排除当前影片本身，最多 12 条。
  Future<List<VodItem>> related(VodItem item) async {
    final selfKey = VodItem.normalizeTitle(item.title);
    try {
      final result = item.isHongguoPrimary
          ? await recommendShortDrama()
          : await recommendByType();
      final related = result.items
          .where((e) => VodItem.normalizeTitle(e.title) != selfKey)
          .toList();
      return related.length > 12 ? related.sublist(0, 12) : related;
    } catch (_) {
      return const <VodItem>[];
    }
  }

  /// 统一搜索：红果 + 18 个采集源并行，分组去重后按相关性排序。
  /// 单源失败静默跳过。
  Future<List<VodItem>> searchAll(String query, {int page = 1}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <VodItem>[];
    final normalizedQuery = VodItem.normalizeTitle(trimmed);

    final futures = <Future<List<VodItem>>>[
      _hongguo.search(trimmed, page: page).then<List<VodItem>>(
            (r) => r.items,
            onError: (_) => const <VodItem>[],
          ),
      for (final api in cmsApis)
        api.search(trimmed, page: page).then<List<VodItem>>(
              (r) => r.items,
              onError: (_) => const <VodItem>[],
            ),
    ];
    final results = await Future.wait(futures);
    return groupSearchResults(results.expand((e) => e).toList(), normalizedQuery);
  }

  /// 搜索分组去重（纯函数，便于单元测试）：
  /// 同名（归一化标题相同）合并为一卡；红果做主键；按相关性排序；
  /// 标题与关键词零重叠的去掉。
  static List<VodItem> groupSearchResults(
    List<VodItem> items,
    String normalizedQuery,
  ) {
    // 1. 按归一化标题分组，组内合并来源。
    final groups = <String, List<VodItem>>{};
    final order = <String>[];
    for (final item in items) {
      final key = VodItem.normalizeTitle(item.title);
      if (key.isEmpty) continue;
      if (!groups.containsKey(key)) {
        groups[key] = <VodItem>[];
        order.add(key);
      }
      groups[key]!.add(item);
    }

    final cards = <_ScoredCard>[];
    for (final key in order) {
      final group = groups[key]!;
      // 2. 相关性：精确相等 > 开头命中 > 包含命中 > 零重叠（去掉）。
      final int score;
      if (key == normalizedQuery) {
        score = 3;
      } else if (key.startsWith(normalizedQuery)) {
        score = 2;
      } else if (key.contains(normalizedQuery)) {
        score = 1;
      } else {
        continue;
      }
      // 3. 主键：组内有红果条目就用红果做主键；否则取注册表
      // 顺序最靠前的采集源（ikun 优先）。
      final hongguoItem = group.where((e) => e.source == 'hongguo').firstOrNull;
      VodItem primary;
      if (hongguoItem != null) {
        primary = hongguoItem;
      } else {
        final cmsOrder = <String, int>{
          for (var i = 0; i < kCmsSources.length; i++) kCmsSources[i].code: i,
        };
        final sorted = List<VodItem>.of(group)
          ..sort((a, b) => (cmsOrder[a.source] ?? 999)
              .compareTo(cmsOrder[b.source] ?? 999));
        primary = sorted.first;
      }
      final sources = <SourceRef>[];
      for (final item in group) {
        sources.addAll(item.sources);
      }
      // 去重 sources（同源只留一个）。
      final seen = <String>{};
      final uniqueSources =
          sources.where((s) => seen.add(s.code)).toList();
      // 主键来源排在 sources 首位。
      uniqueSources.sort((a, b) {
        if (a.code == primary.source && b.code != primary.source) return -1;
        if (b.code == primary.source && a.code != primary.source) return 1;
        return 0;
      });
      cards.add(
        _ScoredCard(
          card: primary.copyWith(sources: uniqueSources),
          score: score,
          hasHongguo: hongguoItem != null,
        ),
      );
    }

    // 4. 排序：相关性高在前；同等相关性红果组在前；再按原顺序。
    cards.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      if (a.hasHongguo != b.hasHongguo) return a.hasHongguo ? -1 : 1;
      return 0;
    });
    return cards.map((c) => c.card).toList();
  }

  /// 详情聚合：红果 detail + 各采集源 detail 并行，单路失败不影响
  /// 另一路；采集源按来源代号路由到对应源的接口，并记录各源
  /// 详情耗时（选源测速的回落依据）。
  Future<DetailResult> detail(VodItem item) async {
    HongguoSeries? hongguoSeries;
    final cmsItems = <String, VodItem>{};
    final detailMs = <String, int>{};
    final futures = <Future<void>>[];

    final hongguoRef = item.sources
        .where((s) => s.code == 'hongguo')
        .firstOrNull;
    if (hongguoRef != null) {
      futures.add(
        () async {
          final sw = Stopwatch()..start();
          try {
            hongguoSeries = await _hongguo.detail(hongguoRef.id);
          } catch (_) {
            // 单路失败不影响另一路。
          } finally {
            detailMs['hongguo'] = sw.elapsedMilliseconds;
          }
        }(),
      );
    }
    for (final ref in item.sources.where((s) => s.code != 'hongguo')) {
      final api = _cmsApis[ref.code];
      if (api == null) continue;
      futures.add(
        () async {
          final sw = Stopwatch()..start();
          try {
            final r = await api.detail(ref.id);
            if (r.items.isNotEmpty) cmsItems[ref.code] = r.items.first;
          } catch (_) {
            // 单路失败不影响另一路。
          } finally {
            detailMs[ref.code] = sw.elapsedMilliseconds;
          }
        }(),
      );
    }
    await Future.wait(futures);
    if (hongguoSeries == null && cmsItems.isEmpty) {
      throw ApiException.server('detail empty');
    }
    return DetailResult(
      item: item,
      hongguoSeries: hongguoSeries,
      cmsItems: cmsItems,
      detailMs: detailMs,
    );
  }

  /// 选源测速（与网页端 pickFastestPlaySource 同一逻辑）：
  /// 详情页加载后在用户网络上实测各源首集是否可直连、耗时多少，
  /// 取最快且可直连的源；红果也参与测速（playinfo + CDN HEAD），
  /// 但不是默认首选——没测出结果前按源列表顺序。
  /// 直连都失败时按详情耗时取最快；无任何候选时返回 null。
  Future<String?> pickFastestSource(DetailResult detail) async {
    final probes = <Future<SourceProbe>>[];
    if (detail.hongguoSeries != null) {
      probes.add(_probeHongguo(detail));
    }
    for (final entry in detail.cmsItems.entries) {
      probes.add(_probeCms(entry.key, entry.value));
    }
    if (probes.isEmpty) return null;
    final results = await Future.wait(probes);
    return selectFastest(results, detail.detailMs);
  }

  /// 选源（纯函数，便于单元测试）：
  /// 可直连的取耗时最短的；都不行时按详情耗时取最快；
  /// 再没有就返回 null（调用方保持原默认源）。
  static String? selectFastest(
    List<SourceProbe> probes,
    Map<String, int> detailMs,
  ) {
    final direct = probes.where((p) => p.direct).toList();
    if (direct.isNotEmpty) {
      direct.sort((a, b) => a.ms.compareTo(b.ms));
      return direct.first.code;
    }
    // 直连全失败：按详情耗时取最快。
    String? best;
    var bestMs = 1 << 30;
    for (final entry in detailMs.entries) {
      if (entry.value >= 0 && entry.value < bestMs) {
        bestMs = entry.value;
        best = entry.key;
      }
    }
    return best;
  }

  /// 探红果：playinfo（第 1 集）计时 + CDN 地址 HEAD 计时。
  Future<SourceProbe> _probeHongguo(DetailResult detail) async {
    final series = detail.hongguoSeries!;
    final sw = Stopwatch()..start();
    try {
      final info = await _hongguo.playinfo(
        seriesId: series.id,
        episodeIndex: 0,
      );
      final head = await _httpClient.probeMedia(info.videoUrl);
      final ms = sw.elapsedMilliseconds;
      return SourceProbe(
        code: 'hongguo',
        ms: ms,
        direct: head.ok,
      );
    } catch (_) {
      return SourceProbe(
        code: 'hongguo',
        ms: -1,
        direct: false,
      );
    }
  }

  /// 探采集源：首集直链探针（m3u8 须读到 #EXTM3U，mp4 HEAD 200）。
  Future<SourceProbe> _probeCms(String code, VodItem cmsItem) async {
    final url = _firstCmsEpisodeUrl(cmsItem);
    if (url == null || url.isEmpty) {
      return SourceProbe(code: code, ms: -1, direct: false);
    }
    final result = await _httpClient.probeMedia(url);
    return SourceProbe(code: code, ms: result.ms, direct: result.ok);
  }

  /// 采集源首集直链（第一个播放组的第一集）。
  static String? _firstCmsEpisodeUrl(VodItem cmsItem) {
    for (final group in cmsItem.playGroups) {
      if (group.episodes.isNotEmpty) return group.episodes.first.url;
    }
    return null;
  }
}

class _ScoredCard {
  const _ScoredCard({
    required this.card,
    required this.score,
    required this.hasHongguo,
  });

  final VodItem card;
  final int score;
  final bool hasHongguo;
}
