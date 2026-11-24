import '../core/config.dart';
import '../core/http_client.dart';
import 'models.dart';

/// 红果客户端：只调自家 EdgeOne 的 /hongguo/* 接口。
///
/// 绝不直调红果官方接口、不自己注册设备、不自己做签名。
/// 签名、设备注册、取址、解密密钥全部由 EdgeOne 层承担，
/// 客户端只传 seriesId/episodeId，拿回播放地址与密钥。
class HongguoApi {
  HongguoApi({VtvHttpClient? client}) : _client = client ?? VtvHttpClient();

  final VtvHttpClient _client;

  /// 注入的 HTTP 客户端（仓库用它给多源池共用同一个客户端）。
  VtvHttpClient get client => _client;

  void _checkCode(Map<String, dynamic> json, String what) {
    if (json['code'] != 1) {
      throw ApiException.server('$what code=${json['code']}');
    }
  }

  /// 短剧推荐。短剧 Tab 的主力来源。
  Future<VodListResult> recommend({int page = 1}) async {
    final json = await _client.getJson(
      Uri.parse('$kApiBase/hongguo/recommend?page=$page'),
      timeout: kHongguoTimeout,
    );
    _checkCode(json, 'recommend');
    return VodListResult.fromHongguo(json);
  }

  /// 短剧搜索。
  Future<VodListResult> search(String query, {int page = 1}) async {
    final json = await _client.getJson(
      Uri.parse('$kApiBase/hongguo/search').replace(
        queryParameters: {'q': query, 'page': '$page'},
      ),
      timeout: kHongguoTimeout,
    );
    _checkCode(json, 'search');
    return VodListResult.fromHongguo(json);
  }

  /// 剧集详情 + 分集（每集含服务端签发的 streamUrl）。
  Future<HongguoSeries> detail(String seriesId) async {
    final json = await _client.getJson(
      Uri.parse('$kApiBase/hongguo/detail').replace(
        queryParameters: {'series_id': seriesId},
      ),
      timeout: kHongguoTimeout,
    );
    _checkCode(json, 'detail');
    return HongguoSeries.fromJson(json);
  }

  /// 播放信息：CDN 直链 + 16 字节 AES 密钥（未加密时 key 为 null）。
  /// [episodeIndex] 是 0 起的集下标（第 1 集传 0）；也可传 episodeId。
  Future<PlayInfo> playinfo({
    required String seriesId,
    int? episodeIndex,
    String? episodeId,
  }) async {
    final query = <String, String>{'series_id': seriesId};
    if (episodeIndex != null) query['index'] = '$episodeIndex';
    if (episodeId != null) query['episode_id'] = episodeId;
    final json = await _client.getJson(
      Uri.parse('$kApiBase/hongguo/playinfo').replace(queryParameters: query),
      timeout: kHongguoTimeout,
    );
    _checkCode(json, 'playinfo');
    final info = PlayInfo.fromJson(json);
    if (info.videoUrl.isEmpty) {
      throw ApiException.server('playinfo empty videoUrl');
    }
    return info;
  }

  /// 弹幕（仅展示，不发送）。
  Future<List<DanmakuItem>> danmaku({
    required String seriesId,
    int? episodeIndex,
    String? episodeId,
  }) async {
    final query = <String, String>{'series_id': seriesId};
    if (episodeIndex != null) query['index'] = '$episodeIndex';
    if (episodeId != null) query['episode_id'] = episodeId;
    final json = await _client.getJson(
      Uri.parse('$kApiBase/hongguo/danmaku').replace(queryParameters: query),
      timeout: kHongguoTimeout,
    );
    _checkCode(json, 'danmaku');
    final listJson = json['danmaku'];
    final items = <DanmakuItem>[];
    if (listJson is List) {
      for (final item in listJson) {
        if (item is Map<String, dynamic>) {
          items.add(DanmakuItem.fromJson(item));
        }
      }
    }
    return items;
  }
}
