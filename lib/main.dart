import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'api/repository.dart';
import 'ui/category_page.dart';
import 'ui/home_page.dart';
import 'ui/placeholder_page.dart';
import 'ui/responsive.dart';
import 'ui/search_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放器初始化失败（缺 libmpv 等）不阻塞启动：UI 仍能进，
  // 播放页再报“播放失败”。桌面端常见此情况。
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    // ignore: 启动降级，见研究报告 §2.6 参考点 8 的平台 gate 思路。
  }
  runApp(VtvApp(repository: VtvRepository()));
}

/// VTV 客户端根组件。`repository` 可注入，便于测试用假 HTTP 客户端。
class VtvApp extends StatelessWidget {
  const VtvApp({super.key, required this.repository});

  final VtvRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // D-pad 焦点接管：覆盖所有路由/对话框（电视/盒子遥控就绪）。
      builder: Dpad.wrap(),
      home: AppShell(repository: repository),
    );
  }
}

/// 5 Tab 壳：首页 / 分类 / 搜索 / 追剧 / 我的。
/// 自适应：窄屏用底部导航，宽屏（>900）用左侧导航栏。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repository});

  final VtvRepository repository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _labels = ['首页', '分类', '搜索', '追剧', '我的'];
  static const _icons = [
    Icons.home,
    Icons.grid_view,
    Icons.search,
    Icons.playlist_play,
    Icons.person,
  ];

  List<Widget> get _pages => [
        HomePage(repository: widget.repository),
        CategoryPage(repository: widget.repository),
        SearchPage(repository: widget.repository),
        const PlaceholderPage(title: '追剧'),
        const PlaceholderPage(title: '我的'),
      ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = useSideNavigation(constraints.maxWidth);
        final content = CenteredContent(
          child: IndexedStack(index: _index, children: pages),
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        label: Text(_labels[i]),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: content,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            type: BottomNavigationBarType.fixed,
            items: [
              for (var i = 0; i < _labels.length; i++)
                BottomNavigationBarItem(
                  icon: Icon(_icons[i]),
                  label: _labels[i],
                ),
            ],
          ),
        );
      },
    );
  }
}
