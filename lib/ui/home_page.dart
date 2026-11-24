import 'package:flutter/material.dart';

import '../api/models.dart';
import '../api/repository.dart';
import '../core/http_client.dart';
import 'detail_page.dart';
import 'vod_card.dart';

/// 首页：顶部 5 个 Tab（电影/电视剧/综艺/动漫/短剧）+ 推荐流。
///
/// - 短剧 Tab 是主力，只拉红果 recommend；
/// - 其余 Tab 拉 18 个采集源资源榜并行合并去重
///   （recommendByType，不传 type，整榜推荐流）；
/// - 卡片一影片一卡，点卡进详情；下拉刷新 + 滑到底分页加载更多。
/// - 默认选中短剧 Tab（短剧是 VTV 短剧主力，也是 M1 最小链路的入口）。
/// - 列数、字号全部随宽度变（见 responsive.dart），不写死。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository});

  final VtvRepository repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['电影', '电视剧', '综艺', '动漫', '短剧'];

  /// 短剧 Tab 的下标。
  static const int shortDramaTabIndex = 4;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: shortDramaTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [for (final label in _tabs) Tab(text: label)],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _HomeTabFeed(
                  repository: widget.repository,
                  tabIndex: i,
                  isShortDrama: i == shortDramaTabIndex,
                  onSelect: _openDetail,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一个 Tab 的推荐流：下拉刷新 + 分页加载更多。
/// AutomaticKeepAlive：切 Tab 不丢已拉到的列表。
class _HomeTabFeed extends StatefulWidget {
  const _HomeTabFeed({
    required this.repository,
    required this.tabIndex,
    required this.isShortDrama,
    required this.onSelect,
  });

  final VtvRepository repository;
  final int tabIndex;
  final bool isShortDrama;
  final ValueChanged<VodItem> onSelect;

  @override
  State<_HomeTabFeed> createState() => _HomeTabFeedState();
}

class _HomeTabFeedState extends State<_HomeTabFeed>
    with AutomaticKeepAliveClientMixin {
  final List<VodItem> _items = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<VodListResult> _fetch(int page) {
    if (widget.isShortDrama) {
      return widget.repository.recommendShortDrama(page: page);
    }
    return widget.repository.recommendByType(page: page);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 1 : _page + 1;
      final result = await _fetch(page);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
          _page = 1;
        } else {
          // 分页追加时按 id 去重（服务端偶尔会回重复页）。
          final seen = _items.map((e) => e.id).toSet();
          _items.addAll(result.items.where((e) => seen.add(e.id)));
          _page = page;
        }
        // pageCount 为 0（接口没给）时按“本页为空”判断是否到底。
        _hasMore = result.pageCount == 0
            ? result.items.isNotEmpty
            : page < result.pageCount;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.userMessage
            : '内容暂时获取失败，请稍后重试';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollEndNotification ||
        notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels >= metrics.maxScrollExtent - 200 &&
          !_loadingMore &&
          _hasMore &&
          !_loading) {
        _load(reset: false);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridKey = widget.isShortDrama
            ? const Key('short-drama-grid')
            : Key('home-grid-${widget.tabIndex}');
        return RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: GridView.builder(
              key: gridKey,
              padding: const EdgeInsets.all(12),
              gridDelegate: vodGridDelegate(constraints.maxWidth),
              itemCount: _items.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final item = _items[index];
                return VodCard(
                  item: item,
                  autofocus: index == 0,
                  onSelect: () => widget.onSelect(item),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
