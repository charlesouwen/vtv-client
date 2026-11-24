# VTV Client

VTV multi-platform client — Flutter + media_kit video aggregator client for [411081.xyz](https://411081.xyz) (Android / Android TV / Windows / Linux).

VTV（411081.xyz）多端客户端：基于 Flutter + media_kit 的影视聚合播放客户端，覆盖 Android 手机、Android TV / 电视盒子、Windows、Linux。

## M1 目标

M1 只做最小可验证骨架，不做完整业务：

- Flutter 工程可跑通，`flutter build apk --release` 能出包；
- media_kit 播放器能播一个直链视频；
- Android TV / 盒子遥控器方向键（D-pad）焦点导航能用；
- 调通 VTV 自家 EdgeOne 服务（https://411081.xyz）的一个真实接口。

M1 不做：完整分类/搜索/详情/选集 UI、弹幕、下载、账号登录。

## 技术栈

- Flutter 3.38.5
- media_kit（libmpv）播放器
- D-pad 焦点导航（Android TV / 盒子遥控器）

## 接口说明

客户端只调 VTV 自家服务，**不直调红果、不接豆瓣**：

- 基础地址：`https://411081.xyz`
- 红果短剧：`/hongguo/*`（EdgeOne 侧完成签名、解密，客户端只拿播放地址/播放信息）
- 采集站资源：AppleCMS 源（经 VTV 自家服务聚合返回）

播放、解密、签名等重活都在 VTV 服务端完成；客户端只负责展示与播放。

## 开发

```sh
flutter pub get
flutter run
```

打包 Android APK：

```sh
flutter build apk --release
```

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。

## M1 骨架（已落地，见 git log）

- `lib/core/`：配置（API_BASE、超时/重试常量）与带超时重试的 HTTP 封装。
- `lib/api/`：`models.dart`（统一 VodItem/PlayInfo/弹幕等）、`hongguo.dart`
  （只调自家 `/hongguo/*`）、`applecms.dart`（ikun 源）、`repository.dart`
  （统一搜索分组去重、红果主键、详情聚合）。
- `lib/player/`：`VtvPlayer`（media_kit 封装；红果 key 经
  `demuxer-lavf-o decryption_key` 交 mpv，失败回落 `/hongguo/stream`）。
- `lib/ui/`：5 Tab 壳 + 最小版首页（短剧 recommend 网格）+ 详情占位页
  + 播放页；分类/搜索/追剧/我的完整 UI 是后续任务。
- 自适应布局（`lib/ui/responsive.dart`）：断点 <600 / 600–900 / >900；
  窄屏底部导航 + 2–3 列，中屏 3–4 列，宽屏左侧导航栏 + 4–6 列、内容区
  居中限宽 1200；详情页宽屏左右排、窄屏上下排；播放页控制栏宽屏多一格时长。
- 测试：`flutter test`（29 个），fixture 是 2026-11-24 的真实响应裁剪版，
  见 `test/fixtures/` 与各测试文件头注释；`flutter analyze` 零问题。
- 未验证：`flutter build linux`（沙箱无 clang++）、真机播放画面与
  Android TV 真机遥控；见 M0 报告同款限制。
