import '../core/config.dart';
import '../core/http_client.dart';
import 'models.dart';

/// AppleCMS 采集源客户端（一个实例对应一个源；18 源的池子由
/// VtvRepository 按 lib/api/cms_sources.dart 的注册表建立）。
/// 原生客户端没有 CORS 限制，直调源站，不走 EdgeOne /proxy/。
class AppleCmsApi {
  AppleCmsApi({
    VtvHttpClient? client,
    String apiBase = kIkunApi,
    this.sourceCode = 'ikun',
    this.sourceName = 'ikun',
  }) : _client = client ?? VtvHttpClient(),
       _apiBase = apiBase;

  final VtvHttpClient _client;
  final String _apiBase;
  final String sourceCode;
  final String sourceName;

  /// 注入的 HTTP 客户端（仓库用它给多源池共用同一个客户端，
  /// 测试里共用同一个假客户端）。
  VtvHttpClient get client => _client;

  Future<VodListResult> _videolist(Map<String, String> params) async {
    final query = <String, String>{'ac': 'videolist', ...params};
    final json = await _client.getJson(
      Uri.parse(_apiBase).replace(queryParameters: query),
      timeout: kCmsTimeout,
    );
    if (json['code'] != 1) {
      throw ApiException.server('cms code=${json['code']}');
    }
    return VodListResult.fromAppleCms(
      json,
      sourceCode: sourceCode,
      sourceName: sourceName,
    );
  }

  /// 搜索：GET {api}?ac=videolist&wd={关键词}&pg={页}
  Future<VodListResult> search(String keyword, {int page = 1}) {
    return _videolist({'wd': keyword, 'pg': '$page'});
  }

  /// 详情：GET {api}?ac=videolist&ids={vod_id}（分集在 vod_play_url 里）。
  Future<VodListResult> detail(String ids) {
    return _videolist({'ids': ids});
  }

  /// 分类浏览：GET {api}?ac=videolist&t={type_id}&pg={页}&year={年份}
  /// 各源 type_id 不统一，归一化映射表由分类页子代理维护。
  Future<VodListResult> list(int? typeId, {int page = 1, int? year}) {
    final params = <String, String>{'pg': '$page'};
    if (typeId != null) params['t'] = '$typeId';
    if (year != null) params['year'] = '$year';
    return _videolist(params);
  }
}
