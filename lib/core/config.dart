/// VTV 客户端全局配置。
///
/// 客户端只调自家 EdgeOne 服务（https://411081.xyz）与采集源 AppleCMS
/// 接口，绝不直调红果官方接口、不自己注册设备、不自己做签名。
/// 签名、设备、取址全部由 EdgeOne 层承担。
library;

/// 自家 EdgeOne 服务地址：红果短剧全部接口都在这里。
const String kApiBase = 'https://411081.xyz';

/// 采集源（AppleCMS）：18 源注册表见 lib/api/cms_sources.dart，
/// 默认 ikun；VtvRepository 按注册表建池。
const String kIkunApi = 'https://ikunzyapi.com/api.php/provide/vod';

/// 红果接口超时：EdgeOne 侧要做签名与取址，比采集源慢。
const Duration kHongguoTimeout = Duration(seconds: 20);

/// 采集源接口超时：直调源站，快失败、快切换。
const Duration kCmsTimeout = Duration(seconds: 8);

/// 可重试错误的最多尝试次数（含首次）。
const int kMaxAttempts = 2;

/// 两次尝试之间的等待。
const Duration kRetryDelay = Duration(seconds: 1);

/// 红果 CDN 请求头（M0 报告实测：不带阅读客户端 UA/Referer 时
/// CDN 可能直接 403；mpv 的 HTTP 层必须显式设置）。
const String kCdnUserAgent = 'com.dragon.read';
const String kCdnReferer = 'https://reading.snssdk.com/';

/// 海报：红果返回的图常是 HEIC，Chrome/部分 Flutter 解码器解不了，
/// 走 weserv 转 JPG 兜底（网页端 fs28 已验证的链路）。
String displayPosterUrl(String url) {
  if (url.isEmpty) return url;
  if (!url.toLowerCase().contains('.heic')) return url;
  final withoutScheme = url.replaceFirst(RegExp(r'^https?://'), '');
  return 'https://images.weserv.nl/?url=${Uri.encodeComponent(withoutScheme)}'
      '&output=jpg';
}
