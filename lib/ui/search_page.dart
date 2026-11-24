import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/repository.dart';
import '../core/http_client.dart';
import '../core/prefs.dart';
import 'detail_page.dart';
import 'vod_card.dart';

/// 搜索结果分组（纯函数，便于测试）。
///
/// repository.searchAll 已按相关性排好（精确 > 开头 > 包含，同级红果
/// 在前）并去掉了零重叠结果；这里只按标题形态再分两组展示：
/// - “命中”：标题与关键词精确相等，或以关键词开头；
/// - “猜你喜欢”：标题包含关键词，但不是开头命中。
/// 组内顺序保持 repository 的顺序（同等相关性下红果卡在前）。
({List<VodItem> matched, List<VodItem> suggested}) groupSearchDisplay(
  List<VodItem> items,
  String query,
) {
  final normalizedQuery = VodItem.normalizeTitle(query);
  final matched = <VodItem>[];
  final suggested = <VodItem>[];
  for (final item in items) {
    final title = VodItem.normalizeTitle(item.title);
    if (title == normalizedQuery || title.startsWith(normalizedQuery)) {
      matched.add(item);
    } else if (title.contains(normalizedQuery)) {
      suggested.add(item);
    }
  }
  return (matched: matched, suggested: suggested);
}

/// 搜索页：搜索框 + 搜索历史（本地存）+ 热搜占位；
/// 结果按“命中”在上、“猜你喜欢”在下分组，红果主键卡片在前。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository});

  final VtvRepository repository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  static const _hotKeywords = ['重生', '穿越', '仙侠', '总裁', '年代', '甜宠'];

  final TextEditingController _controller = TextEditingController();
  SharedPreferences? _prefs;
  List<String> _history = [];
  String? _submittedQuery;
  List<VodItem> _results = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      try {
        _history = prefs?.getStringList(kPrefSearchHistory) ?? const [];
      } catch (_) {
        _history = [];
      }
    });
  }

  Future<void> _saveHistory(String query) async {
    final updated = [query, ..._history.where((h) => h != query)];
    final trimmed = updated.length > 10 ? updated.sublist(0, 10) : updated;
    setState(() => _history = trimmed);
    try {
      await _prefs?.setStringList(kPrefSearchHistory, trimmed);
    } catch (_) {}
  }

  Future<void> _submit(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    _controller.text = query;
    await _saveHistory(query);
    setState(() {
      _submittedQuery = query;
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final results = await widget.repository.searchAll(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        // searchAll 一次返回一页；有结果就允许再拉一页试试。
        _hasMore = results.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.userMessage
            : '内容暂时获取失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final query = _submittedQuery;
    if (query == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.repository.searchAll(query, page: _page + 1);
      if (!mounted) return;
      setState(() {
        if (next.isEmpty) {
          _hasMore = false;
        } else {
          _page += 1;
          final seen = _results.map((e) => e.id).toSet();
          _results = [
            ..._results,
            ...next.where((e) => !seen.contains(e.id)),
          ];
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openDetail(VodItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(item: item, repository: widget.repository),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('search-field'),
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  decoration: InputDecoration(
                    hintText: '搜索影片、短剧',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _submittedQuery == null
                        ? null
                        : IconButton(
                            key: const Key('search-clear'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _controller.clear();
                                _submittedQuery = null;
                                _results = [];
                                _error = null;
                              });
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('search-submit'),
                onPressed: () => _submit(_controller.text),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_submittedQuery == null) return _buildHome();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _submit(_submittedQuery!),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('没有找到相关内容，换个关键词试试'));
    }
    final groups = groupSearchDisplay(_results, _submittedQuery!);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groups.matched.isNotEmpty) ...[
            _sectionTitle('命中', key: const Key('section-matched')),
            VodCardGrid(
              items: groups.matched,
              onSelect: _openDetail,
              gridKey: const Key('search-matched-grid'),
            ),
          ],
          if (groups.suggested.isNotEmpty) ...[
            _sectionTitle('猜你喜欢', key: const Key('section-suggested')),
            VodCardGrid(
              items: groups.suggested,
              onSelect: _openDetail,
              gridKey: const Key('search-suggested-grid'),
            ),
          ],
          if (_hasMore)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        key: const Key('search-load-more'),
                        onPressed: _loadMore,
                        child: const Text('加载更多'),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                Text('搜索历史', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  key: const Key('search-history-clear'),
                  onPressed: () async {
                    setState(() => _history = []);
                    try {
                      await _prefs?.remove(kPrefSearchHistory);
                    } catch (_) {}
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              key: const Key('search-history'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final keyword in _history)
                  ActionChip(
                    label: Text(keyword),
                    onPressed: () => _submit(keyword),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Text('热搜', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            key: const Key('hot-search'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in _hotKeywords)
                ActionChip(
                  label: Text(keyword),
                  onPressed: () => _submit(keyword),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
