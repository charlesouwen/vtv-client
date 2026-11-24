import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 安全读写：测试环境（未设 mock）或平台异常时
/// 返回 null / 忽略，不让偏好读写拖垮页面。
Future<SharedPreferences?> loadPrefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

/// 读 double 偏好，读不到返回 [fallback]。
double readDoublePref(SharedPreferences? prefs, String key, double fallback) {
  if (prefs == null) return fallback;
  try {
    return prefs.getDouble(key) ?? fallback;
  } catch (_) {
    return fallback;
  }
}

/// 读 bool 偏好，读不到返回 [fallback]。
bool readBoolPref(SharedPreferences? prefs, String key, bool fallback) {
  if (prefs == null) return fallback;
  try {
    return prefs.getBool(key) ?? fallback;
  } catch (_) {
    return fallback;
  }
}

/// 写 double 偏好，失败忽略。
Future<void> writeDoublePref(
  SharedPreferences? prefs,
  String key,
  double value,
) async {
  if (prefs == null) return;
  try {
    await prefs.setDouble(key, value);
  } catch (_) {}
}

/// 写 bool 偏好，失败忽略。
Future<void> writeBoolPref(
  SharedPreferences? prefs,
  String key,
  bool value,
) async {
  if (prefs == null) return;
  try {
    await prefs.setBool(key, value);
  } catch (_) {}
}

/// 播放页偏好键。
const String kPrefVolume = 'vtv_volume';
const String kPrefRate = 'vtv_rate';
const String kPrefDanmakuEnabled = 'vtv_danmaku_enabled';

/// 搜索历史键（最近 10 条）。
const String kPrefSearchHistory = 'vtv_search_history';
