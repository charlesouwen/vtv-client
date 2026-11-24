/// AppleCMS 采集源注册表（与 VTV 网页端 edgeone/js/config.js 的
/// API_SITES 逐项一致：代号、展示名、api 地址）。
///
/// 客户端直调源站（原生无 CORS，不走 EdgeOne /proxy/）。
/// 红果不在此表——红果走自家 EdgeOne /hongguo/*，见 lib/api/hongguo.dart。
library;

/// 一个 AppleCMS 采集源。
class CmsSource {
  const CmsSource({
    required this.code,
    required this.name,
    required this.apiBase,
  });

  /// 来源代号，与网页端 API_SITES 的键一致（如 'ikun'）。
  final String code;

  /// 展示名（如“iKun资源”），与网页端一致。
  final String name;

  /// AppleCMS 接口地址（`?ac=videolist` 形态）。
  final String apiBase;
}

/// 18 个采集源。ikun 排第一：它是 VTV 网页端的默认源，也是
/// 客户端合并去重时的主键优先源。
const List<CmsSource> kCmsSources = [
  CmsSource(
    code: 'ikun',
    name: 'iKun资源',
    apiBase: 'https://ikunzyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'dyttzy',
    name: '电影天堂资源',
    apiBase: 'http://caiji.dyttzyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'ruyi',
    name: '如意资源',
    apiBase: 'https://cj.rycjapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'bfzy',
    name: '暴风资源',
    apiBase: 'https://bfzyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'tyyszy',
    name: '天涯资源',
    apiBase: 'https://tyyszy.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'ffzy',
    name: '非凡影视',
    apiBase: 'http://ffzy5.tv/api.php/provide/vod',
  ),
  CmsSource(
    code: 'zy360',
    name: '360资源',
    apiBase: 'https://360zy.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'iqiyi',
    name: 'iqiyi资源',
    apiBase: 'https://www.iqiyizyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'jisu',
    name: '极速资源',
    apiBase: 'https://jszyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'dbzy',
    name: '豆瓣资源',
    apiBase: 'https://dbzy.tv/api.php/provide/vod',
  ),
  CmsSource(
    code: 'mdzy',
    name: '魔都资源',
    apiBase: 'https://www.mdzyapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'zuid',
    name: '最大资源',
    apiBase: 'https://api.zuidapi.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'yinghua',
    name: '樱花资源',
    apiBase: 'https://m3u8.apiyhzy.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'baidu',
    name: '百度云资源',
    apiBase: 'https://api.apibdzy.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'wujin',
    name: '无尽资源',
    apiBase: 'https://api.wujinapi.me/api.php/provide/vod',
  ),
  CmsSource(
    code: 'lzi',
    name: '量子资源站',
    apiBase: 'https://cj.lziapi.com/api.php/provide/vod/',
  ),
  CmsSource(
    code: 'subo',
    name: '速播资源',
    apiBase: 'https://subocaiji.com/api.php/provide/vod',
  ),
  CmsSource(
    code: 'ukzy',
    name: 'U酷资源',
    apiBase: 'https://api.ukuapi88.com/api.php/provide/vod',
  ),
];

/// 默认采集源（VTV 网页端默认源）。
final CmsSource kDefaultCmsSource = kCmsSources.first;

/// 按代号索引。
final Map<String, CmsSource> kCmsSourcesByCode = {
  for (final s in kCmsSources) s.code: s,
};

/// 分类浏览可用的源：只有 ikun / ruyi / bfzy 三源的 type_id
/// 经过网页端实测归一（见 lib/api/category_map.dart），其余
/// 15 源的类型树未验证，分类不拉它们（搜索/推荐/详情仍全量）。
const List<String> kCategorySourceCodes = ['ikun', 'ruyi', 'bfzy'];

/// 服务端认 `year` 参数的源（网页端实测：bfzy、ikun 支持；
/// ruyi 不支持，客户端按 vod_year 过滤）。
/// 其余源未验证 year 支持情况，分类时不传 year，靠客户端过滤。
const Set<String> kCmsYearSupported = {'ikun', 'bfzy'};
