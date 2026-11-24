import 'package:flutter/material.dart';

import '../api/category_map.dart';
import '../api/models.dart';
import '../api/repository.dart';
import '../core/http_client.dart';
import 'detail_page.dart';
import 'vod_card.dart';

/// 分类页（一等功能）：大类 → 子类 → 年份 + 排序 + 分页。
///
/// 数据源：
/// - 电影/电视剧/综艺/动漫：ikun / ruyi / bfzy 三源 `?ac=videolist`
///   （type_id 归一化映射见 lib/api/category_map.dart；其余 15 源
///   类型树未验证，分类不拉它们）；ikun、bfzy 认 `year` 参数服务端筛，
///   ruyi 不认，客户端按 vod_year 过滤；“更早”为 vod_year ≤ 2021
///   客户端过滤；排序一律客户端做（最新 = vod_time 降序，最热 = vod_hits 降序）。
/// - 短剧：题材走红果 search（每题材拉两页），暴风按题材 type_id
///   作补充混入；红果条目无年份/时间/热度，指定年份时红果豁免
///   年份过滤（“更早”除外）、排序时红果组在前。
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.repository});

  final VtvRepository repository;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  TopCategory _top = TopCategory.movie;
  int _subIndex = 0;
  YearFilter _year = YearFilter.all;
  CategorySort _sort = CategorySort.latest;

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

  List<SubCategory> get _subs => kCategoryTree[_top]!;

  SubCategory get _sub => _subs[_subIndex];

  /// 拉一页数据（短剧题材一次拉两页并合并去重）。
  Future<List<VodItem>> _fetchPage(int page) async {
    if (_top.isShortDrama) {
      if (_subIndex == 0) {
        // “全部”题材：红果推荐流。
        final first = await widget.repository.recommendShortDrama(
          page: page * 2 - 1,
        );
        final second = await widget.repository.recommendShortDrama(
          page: page * 2,
        );
        return _mergeDedupe([first, second]);
      }
      final first = await widget.repository.shortDramaTheme(
        _sub.label,
        page: page * 2 - 1,
      );
      final second = await widget.repository.shortDramaTheme(
        _sub.label,
        page: page * 2,
      );
      return _mergeDedupe([first, second]);
    }
    final result = await widget.repository.categoryList(
      sub: _sub,
      year: _year,
      page: page,
    );
    return result.items;
  }

  List<VodItem> _mergeDedupe(List<VodListResult> pages) {
    final seen = <String>{};
    final merged = <VodItem>[];
    for (final page in pages) {
      for (final item in page.items) {
        if (seen.add(item.id)) merged.add(item);
      }
    }
    return merged;
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
      final fetched = await _fetchPage(page);
      if (!mounted) return;
      setState(() {
        final base = reset ? <VodItem>[] : List<VodItem>.of(_items);
        // 追加时按 id 去重（服务端偶尔会回重复页）。
        final seen = base.map((e) => e.id).toSet();
        base.addAll(fetched.where((e) => seen.add(e.id)));
        // 年份过滤 + 排序一律客户端做（短剧红果条目按规则豁免/置前）。
        final filtered = filterCategoryByYear(base, _year);
        _items
          ..clear()
          ..addAll(sortCategoryItems(filtered, _sort));
        _page = page;
        _hasMore = fetched.isNotEmpty;
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

  void _changeTop(TopCategory top) {
    if (top == _top) return;
    setState(() {
      _top = top;
      _subIndex = 0;
    });
    _load(reset: true);
  }

  void _changeSub(int index) {
    if (index == _subIndex) return;
    setState(() => _subIndex = index);
    _load(reset: true);
  }

  void _changeYear(YearFilter year) {
    if (year == _year) return;
    setState(() => _year = year);
    _load(reset: true);
  }

  void _changeSort(CategorySort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _load(reset: true);
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

  void _openDetail(VodItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(item: item, repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterRow(
          key: const Key('category-top'),
          labels: TopCategory.values.map((c) => c.label).toList(),
          selected: _top.index,
          onSelected: (i) => _changeTop(TopCategory.values[i]),
        ),
        _filterRow(
          key: const Key('category-sub'),
          labels: _subs.map((s) => s.label).toList(),
          selected: _subIndex,
          onSelected: _changeSub,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('category-year'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < YearFilter.values.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(YearFilter.values[i].label),
                            selected: _year == YearFilter.values[i],
                            onSelected: (selected) {
                              if (selected) {
                                _changeYear(YearFilter.values[i]);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<CategorySort>(
                key: const Key('category-sort'),
                segments: [
                  for (final sort in CategorySort.values)
                    ButtonSegment<CategorySort>(
                      value: sort,
                      label: Text(sort.label),
                    ),
                ],
                selected: {_sort},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) _changeSort(selected.first);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _filterRow({
    required Key key,
    required List<String> labels,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    return SingleChildScrollView(
      key: key,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[i]),
                selected: selected == i,
                onSelected: (value) {
                  if (value) onSelected(i);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
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
      return const Center(child: Text('该分类下暂无内容'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: GridView.builder(
              key: const Key('category-grid'),
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
                  onSelect: () => _openDetail(item),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
