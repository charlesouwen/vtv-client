/// VTV 统一数据模型。
///
/// 核心产品规则（一影片一卡）：搜索/推荐结果按影片分组去重，
/// 同名只留一张卡，卡内含全部来源（红果 + 采集源）。
library;

/// 一个来源的引用（卡片主键之外的其他来源也记在这里）。
class SourceRef {
const SourceRef({
required this.code,
required this.name,
required this.id,
});

/// 来源代号：'hongguo' 或采集源代号（如 'ikun'）。
final String code;

/// 来源展示名，如“红果短剧”。
final String name;

/// 该来源下的影片 id（红果是 series_id，采集源是 vod_id）。
final String id;
}

/// 采集源一集：标题 + 直链地址。
class CmsEpisode {
const CmsEpisode({required this.title, required this.url});

final String title;
final String url;
}

/// 采集源一个播放组（vod_play_url 里 $$$ 分隔的一组）。
class CmsPlayGroup {
const CmsPlayGroup({required this.name, required this.episodes});

final String name;
final List<CmsEpisode> episodes;
}

/// 解析 AppleCMS 的 vod_play_url：
/// `$$$` 分播放组、`#` 分集、`$` 分隔标题与地址。
List<CmsPlayGroup> parseVodPlayUrl(String raw) {
final groups = <CmsPlayGroup>[];
if (raw.trim().isEmpty) return groups;
final rawGroups = raw.split(r'$$$');
for (var i = 0; i < rawGroups.length; i++) {
final episodes = <CmsEpisode>[];
for (final part in rawGroups[i].split('#')) {
final segment = part.trim();
if (segment.isEmpty) continue;
final dollar = segment.indexOf(r'$');
if (dollar < 0) continue;
final title = segment.substring(0, dollar).trim();
final url = segment.substring(dollar + 1).trim();
if (title.isEmpty || url.isEmpty) continue;
episodes.add(CmsEpisode(title: title, url: url));
}
if (episodes.isNotEmpty) {
groups.add(CmsPlayGroup(name: '线路${i + 1}', episodes: episodes));
}
}
return groups;
}

/// 统一影片卡片：一影片一卡，卡内含全部来源。
class VodItem {
const VodItem({
required this.id,
required this.title,
required this.pic,
required this.year,
required this.area,
required this.typeName,
required this.remarks,
required this.source,
required this.episodeCount,
required this.sources,
this.playGroups = const <CmsPlayGroup>[],
this.content = '',
this.director = '',
this.actor = '',
this.time = '',
this.hits = 0,
});

/// 主键 id：红果主键时是 series_id，采集源主键时是 vod_id。
final String id;
final String title;
final String pic;
final String year;
final String area;
final String typeName;

/// 如“全168集”“更新至13集”。
final String remarks;

/// 主键来源代号：'hongguo' 或采集源代号。
final String source;

/// 集数（从 remarks 解析，如“全168集”→168；解析不到为 null）。
final int? episodeCount;

/// 该影片的全部来源（含主键来源）。
final List<SourceRef> sources;

/// 采集源分集（详情接口解析 vod_play_url 得到；红果卡为空）。
final List<CmsPlayGroup> playGroups;

/// 简介（详情接口才有；列表接口为空）。
final String content;

/// 导演（详情接口才有）。
final String director;

/// 演员（详情接口才有）。
final String actor;

/// 上架/更新时间（AppleCMS vod_time，`YYYY-MM-DD HH:mm:ss`；
/// 红果条目为空）。分类“最新”排序用。
final String time;

/// 点击量（AppleCMS vod_hits；红果条目为 0）。分类“最热”排序用。
final int hits;

bool get isHongguoPrimary => source == 'hongguo';

/// 归一化标题：去空白、去标点、转小写，用于搜索分组去重与
/// 相关性判定。CJK 字符保留。
static String normalizeTitle(String title) {
final lower = title.toLowerCase();
final buffer = StringBuffer();
for (final rune in lower.runes) {
final ch = String.fromCharCode(rune);
if (RegExp(r'\s').hasMatch(ch)) continue;
if (RegExp(r'[，。、；：！？,.!?:;·\-—_()（）《》「」『』\[\]"'"'"'“”‘’/\\|@#\$%^&*+=~`]').hasMatch(ch)) {
continue;
}
buffer.write(ch);
}
return buffer.toString();
}

static int? _parseEpisodeCount(String remarks) {
final match = RegExp(r'(\d+)').firstMatch(remarks);
if (match == null) return null;
return int.tryParse(match.group(1)!);
}

static String _asString(Object? value) =>
value == null? '': value.toString();

/// 红果推荐/搜索条目（EdgeOne /hongguo/* 返回的 AppleCMS 形字段）。
factory VodItem.fromHongguo(Map<String, dynamic> json) {
final id = _asString(json['vod_id']);
final remarks = _asString(json['vod_remarks']);
return VodItem(
id: id,
title: _asString(json['vod_name']),
pic: _asString(json['vod_pic']),
year: _asString(json['vod_year']),
area: _asString(json['vod_area']),
typeName: _asString(json['type_name']),
remarks: remarks,
source: 'hongguo',
episodeCount: _parseEpisodeCount(remarks),
sources: [
SourceRef(code: 'hongguo', name: '红果短剧', id: id),
],
content: _asString(json['vod_content']),
);
}

/// 采集源条目（AppleCMS 标准字段）。
factory VodItem.fromAppleCms(
Map<String, dynamic> json, {
String sourceCode = 'ikun',
String sourceName = 'ikun',
}) {
final id = _asString(json['vod_id']);
final remarks = _asString(json['vod_remarks']);
final rawPlayUrl = _asString(json['vod_play_url']);
return VodItem(
id: id,
title: _asString(json['vod_name']),
pic: _asString(json['vod_pic']),
year: _asString(json['vod_year']),
area: _asString(json['vod_area']),
typeName: _asString(json['type_name']),
remarks: remarks,
source: sourceCode,
episodeCount: _parseEpisodeCount(remarks),
sources: [SourceRef(code: sourceCode, name: sourceName, id: id)],
playGroups: parseVodPlayUrl(rawPlayUrl),
content: _asString(json['vod_content']),
director: _asString(json['vod_director']),
actor: _asString(json['vod_actor']),
time: _asString(json['vod_time']),
hits: json['vod_hits'] is num ? (json['vod_hits'] as num).toInt() : 0,
);
}

VodItem copyWith({
String? id,
String? title,
String? pic,
String? year,
String? area,
String? typeName,
String? remarks,
String? source,
int? episodeCount,
List<SourceRef>? sources,
List<CmsPlayGroup>? playGroups,
String? content,
String? director,
String? actor,
String? time,
int? hits,
}) {
return VodItem(
id: id?? this.id,
title: title?? this.title,
pic: pic?? this.pic,
year: year?? this.year,
area: area?? this.area,
typeName: typeName?? this.typeName,
remarks: remarks?? this.remarks,
source: source?? this.source,
episodeCount: episodeCount?? this.episodeCount,
sources: sources?? this.sources,
playGroups: playGroups?? this.playGroups,
content: content ?? this.content,
director: director ?? this.director,
actor: actor ?? this.actor,
time: time ?? this.time,
hits: hits ?? this.hits,
);
}
}

/// 红果一集。实测 detail 返回的分集字段是 id（"ep-N"）、
/// title、episodeNumber（1 起）、streamUrl；vid 不一定有。
class HongguoEpisode {
const HongguoEpisode({
required this.id,
required this.episodeNumber,
required this.title,
required this.streamUrl,
this.vid,
});

final String id;

/// 集号（1 起）。
final int episodeNumber;
final String title;

/// 服务端签发的 HMAC token 直链（/hongguo/stream/{token}），
/// 播放失败时的回落地址。
final String streamUrl;

/// 红果 vid（有则保留；playinfo 也可用 index 调用，不依赖它）。
final String? vid;

/// playinfo 的 index 参数是 0 起的：第 1 集传 0。
int get playIndex => episodeNumber - 1;

factory HongguoEpisode.fromJson(Map<String, dynamic> json) {
final episodeNumber =
json['episodeNumber'] is num? (json['episodeNumber'] as num).toInt(): 1;
return HongguoEpisode(
id: json['id']?.toString()?? 'ep-$episodeNumber',
episodeNumber: episodeNumber,
title: json['title']?.toString()?? '第$episodeNumber集',
streamUrl: json['streamUrl']?.toString()?? '',
vid: json['vid']?.toString()?? json['r']?.toString(),
);
}
}

/// 红果剧集详情（EdgeOne /hongguo/detail）。
class HongguoSeries {
const HongguoSeries({
required this.id,
required this.title,
required this.pic,
required this.content,
required this.remarks,
required this.typeName,
required this.episodes,
required this.playbackUnavailable,
});

final String id;
final String title;
final String pic;
final String content;
final String remarks;
final String typeName;
final List<HongguoEpisode> episodes;

/// 上游标记该剧暂不可播（ByteVC2 等片源侧原因）。
final bool playbackUnavailable;

factory HongguoSeries.fromJson(Map<String, dynamic> json) {
final episodesJson = json['episodes'];
final episodes = <HongguoEpisode>[];
if (episodesJson is List) {
for (final item in episodesJson) {
if (item is Map<String, dynamic>) {
episodes.add(HongguoEpisode.fromJson(item));
}
}
}
return HongguoSeries(
id: json['vod_id']?.toString()?? '',
title: json['vod_name']?.toString()?? '',
pic: json['vod_pic']?.toString()?? '',
content: json['vod_content']?.toString()?? '',
remarks: json['vod_remarks']?.toString()?? '',
typeName: json['type_name']?.toString()?? '',
episodes: episodes,
playbackUnavailable: json['playbackUnavailable'] == true,
);
}
}

/// playinfo 一个清晰度变体。
class PlayVariant {
const PlayVariant({required this.url, required this.key, required this.codec});

final String url;

/// 16 字节 AES hex；空字符串表示该变体未加密。
final String key;
final String codec;

factory PlayVariant.fromJson(Map<String, dynamic> json) {
return PlayVariant(
url: json['url']?.toString()?? '',
key: json['key']?.toString()?? '',
codec: json['codec']?.toString()?? '',
);
}
}

/// 红果播放信息（EdgeOne /hongguo/playinfo）。
class PlayInfo {
const PlayInfo({
required this.videoUrl,
required this.key,
required this.codec,
required this.quality,
required this.width,
required this.height,
required this.duration,
required this.variants,
this.vid,
});

/// CDN 直链（加密流，需配合 [key] 解密）。
final String videoUrl;

/// 16 字节 AES-CTR 内容密钥 hex；null/空表示未加密。
final String? key;
final String codec;
final String quality;
final int width;
final int height;
final double duration;
final List<PlayVariant> variants;
final String? vid;

bool get encrypted => key!= null && key!.isNotEmpty;

/// 竖屏短剧（高大于宽），播放页/全屏分流用。
bool get isVertical => height > width;

factory PlayInfo.fromJson(Map<String, dynamic> json) {
final variantsJson = json['variants'];
final variants = <PlayVariant>[];
if (variantsJson is List) {
for (final item in variantsJson) {
if (item is Map<String, dynamic>) {
variants.add(PlayVariant.fromJson(item));
}
}
}
return PlayInfo(
videoUrl: json['videoUrl']?.toString()?? '',
key: json['key']?.toString(),
codec: json['codec']?.toString()?? '',
quality: json['quality']?.toString()?? '',
width: json['width'] is num? (json['width'] as num).toInt(): 0,
height: json['height'] is num? (json['height'] as num).toInt(): 0,
duration: json['duration'] is num
? (json['duration'] as num).toDouble()
: 0,
variants: variants,
vid: json['vid']?.toString(),
);
}
}

/// 一条弹幕（EdgeOne /hongguo/danmaku）。仅展示，不发送。
class DanmakuItem {
const DanmakuItem({required this.time, required this.text});

/// 出现时间（秒）。
final double time;
final String text;

factory DanmakuItem.fromJson(Map<String, dynamic> json) {
return DanmakuItem(
time: json['time'] is num? (json['time'] as num).toDouble(): 0,
text: json['text']?.toString()?? '',
);
}
}

/// 列表型接口的通用返回（recommend / search）。
class VodListResult {
const VodListResult({
required this.items,
required this.total,
required this.page,
required this.pageCount,
});

final List<VodItem> items;
final int total;
final int page;
final int pageCount;

static int _asInt(Object? value) {
if (value is num) return value.toInt();
return int.tryParse(value?.toString()?? '')?? 0;
}

factory VodListResult.fromHongguo(Map<String, dynamic> json) {
final listJson = json['list'];
final items = <VodItem>[];
if (listJson is List) {
for (final item in listJson) {
if (item is Map<String, dynamic>) {
items.add(VodItem.fromHongguo(item));
}
}
}
return VodListResult(
items: items,
total: _asInt(json['total']),
page: _asInt(json['page']),
pageCount: _asInt(json['pagecount']),
);
}

factory VodListResult.fromAppleCms(
Map<String, dynamic> json, {
String sourceCode = 'ikun',
String sourceName = 'ikun',
}) {
final listJson = json['list'];
final items = <VodItem>[];
if (listJson is List) {
for (final item in listJson) {
if (item is Map<String, dynamic>) {
items.add(
VodItem.fromAppleCms(
item,
sourceCode: sourceCode,
sourceName: sourceName,
),
);
}
}
}
return VodListResult(
items: items,
total: _asInt(json['total']),
page: _asInt(json['page']),
pageCount: _asInt(json['pagecount']),
);
}
}
