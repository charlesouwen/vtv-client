import 'models.dart';

/// 分类归一化映射表（ikun / ruyi / bfzy 三源实测 type_id，
/// 与网页端 edgeone/js/category.js 的归一表逐项一致）。
///
/// 各采集源 type_id 不统一，只有这三源经过实测归一；其余 15 源
/// 的类型树未验证，分类浏览只拉这三源（搜索/推荐/详情仍全量 18 源）。
/// 短剧题材走红果 search，不占 type_id；暴风题材 id 只作短剧补充。

/// 五个一等大类。
enum TopCategory { movie, tv, variety, anime, shortDrama }

extension TopCategoryLabel on TopCategory {
  String get label {
    switch (this) {
      case TopCategory.movie:
        return '电影';
      case TopCategory.tv:
        return '电视剧';
      case TopCategory.variety:
        return '综艺';
      case TopCategory.anime:
        return '动漫';
      case TopCategory.shortDrama:
        return '短剧';
    }
  }

  /// 短剧走红果题材搜索，其余大类走 ikun ?ac=videolist。
  bool get isShortDrama => this == TopCategory.shortDrama;
}

/// 一个子类：展示名 + 各源 type_id（null/缺失 = 该源没有这个子类）。
class SubCategory {
  const SubCategory(this.label, this.typeIds);

  final String label;

  /// 来源代号 → type_id；缺失表示该源没有这个子类，分类时跳过该源。
  final Map<String, int> typeIds;

  /// ikun type_id（null = 不传 t 参数，即该大类全部）。
  /// 兼容旧调用：categoryList 的 ikun 单源路径仍用它。
  int? get typeId => typeIds['ikun'];

  /// 指定源的 type_id；null 表示该源没有这个子类。
  int? typeIdFor(String sourceCode) => typeIds[sourceCode];
}

/// 大类 → 子类表（ikun / ruyi / bfzy 实测值，与网页端一致）。
const Map<TopCategory, List<SubCategory>> kCategoryTree = {
  TopCategory.movie: [
    SubCategory('全部', {}),
    SubCategory('动作', {'ikun': 6, 'ruyi': 6, 'bfzy': 21}),
    SubCategory('喜剧', {'ikun': 7, 'ruyi': 7, 'bfzy': 22}),
    SubCategory('爱情', {'ikun': 8, 'ruyi': 8, 'bfzy': 25}),
    SubCategory('科幻', {'ikun': 9, 'ruyi': 9, 'bfzy': 24}),
    SubCategory('恐怖', {'ikun': 10, 'ruyi': 10, 'bfzy': 23}),
    SubCategory('剧情', {'ikun': 11, 'ruyi': 11, 'bfzy': 26}),
    SubCategory('战争', {'ikun': 12, 'ruyi': 12, 'bfzy': 27}),
    SubCategory('动画', {'ikun': 22, 'ruyi': 47, 'bfzy': 50}),
    SubCategory('纪录', {'ikun': 20, 'ruyi': 20, 'bfzy': 28}),
  ],
  TopCategory.tv: [
    SubCategory('全部', {}),
    SubCategory('国产', {'ikun': 23, 'ruyi': 13, 'bfzy': 31}),
    SubCategory('香港', {'ikun': 24, 'ruyi': 14, 'bfzy': 33}),
    SubCategory('韩国', {'ikun': 25, 'ruyi': 15, 'bfzy': 34}),
    SubCategory('欧美', {'ikun': 26, 'ruyi': 16, 'bfzy': 32}),
    SubCategory('台湾', {'ikun': 27, 'ruyi': 21, 'bfzy': 35}),
    SubCategory('日本', {'ikun': 28, 'ruyi': 22, 'bfzy': 36}),
    SubCategory('泰国', {'ikun': 30, 'ruyi': 24, 'bfzy': 38}),
    SubCategory('海外', {'ikun': 29, 'ruyi': 23, 'bfzy': 37}),
  ],
  TopCategory.variety: [
    SubCategory('全部', {}),
    SubCategory('大陆', {'ikun': 31, 'ruyi': 25, 'bfzy': 46}),
    SubCategory('港台', {'ikun': 32, 'ruyi': 26, 'bfzy': 47}),
    SubCategory('日韩', {'ikun': 33, 'ruyi': 27, 'bfzy': 48}),
    SubCategory('欧美', {'ikun': 34, 'ruyi': 28, 'bfzy': 49}),
  ],
  TopCategory.anime: [
    SubCategory('全部', {}),
    SubCategory('国产', {'ikun': 35, 'ruyi': 29, 'bfzy': 40}),
    SubCategory('日韩', {'ikun': 37, 'ruyi': 30, 'bfzy': 41}),
    SubCategory('欧美', {'ikun': 36, 'ruyi': 31, 'bfzy': 42}),
    // 港台 / 海外：ikun 没有对应子类，只有 ruyi / bfzy。
    SubCategory('港台', {'ruyi': 32, 'bfzy': 43}),
    SubCategory('海外', {'ruyi': 33, 'bfzy': 44}),
  ],
  // 短剧的子类是题材，走红果 search，不用 type_id。
  TopCategory.shortDrama: [
    SubCategory('全部', {}),
    SubCategory('重生', {}),
    SubCategory('穿越', {}),
    SubCategory('现代言情', {}),
    SubCategory('反转爽文', {}),
    SubCategory('女恋总裁', {}),
    SubCategory('闪婚离婚', {}),
    SubCategory('都市脑洞', {}),
    SubCategory('古装仙侠', {}),
    SubCategory('AI漫剧', {}),
  ],
};

/// 短剧题材 → 暴风（bfzy）补充 type_id（网页端实测）。
/// 短剧以红果搜索为主力，暴风只作补充混入，不单独成类。
const Map<String, int> kShortDramaThemeBfzyTypeId = {
  '重生': 59,
  '穿越': 60,
  '现代言情': 61,
  '反转爽文': 62,
  '女恋总裁': 63,
  '闪婚离婚': 64,
  '都市脑洞': 65,
  '古装仙侠': 66,
  'AI漫剧': 68,
};

/// 短剧题材（红果 search 关键词）。“全部”题材拉红果 recommend。
const List<String> kShortDramaThemes = [
  '重生',
  '穿越',
  '现代言情',
  '反转爽文',
  '女恋总裁',
  '闪婚离婚',
  '都市脑洞',
  '古装仙侠',
  'AI漫剧',
];

/// 年份筛选。
enum YearFilter { all, y2026, y2025, y2024, y2023, y2022, earlier }

extension YearFilterValue on YearFilter {
  String get label {
    switch (this) {
      case YearFilter.all:
        return '全部';
      case YearFilter.y2026:
        return '2026';
      case YearFilter.y2025:
        return '2025';
      case YearFilter.y2024:
        return '2024';
      case YearFilter.y2023:
        return '2023';
      case YearFilter.y2022:
        return '2022';
      case YearFilter.earlier:
        return '更早';
    }
  }

  /// 传给 ikun `year` 参数的值；null 表示服务端不过滤。
  /// “更早”是客户端过滤（vod_year ≤ 2021），也不传 year。
  int? get serverYear {
    switch (this) {
      case YearFilter.all:
        return null;
      case YearFilter.y2026:
        return 2026;
      case YearFilter.y2025:
        return 2025;
      case YearFilter.y2024:
        return 2024;
      case YearFilter.y2023:
        return 2023;
      case YearFilter.y2022:
        return 2022;
      case YearFilter.earlier:
        return null;
    }
  }
}

/// 排序：一律客户端做。
enum CategorySort { latest, hottest }

extension CategorySortLabel on CategorySort {
  String get label {
    switch (this) {
      case CategorySort.latest:
        return '最新';
      case CategorySort.hottest:
        return '最热';
    }
  }
}

/// 客户端年份过滤（纯函数）。
///
/// - 指定年份（2022–2026）：ikun 已由服务端筛过，这里只补一道；
///   红果条目无年份，豁免（保留）。
/// - “更早”：vod_year ≤ 2021 才留；红果条目无年份，不豁免（去掉）。
/// - 全部：不过滤。
List<VodItem> filterCategoryByYear(List<VodItem> items, YearFilter year) {
  if (year == YearFilter.all) return items;
  if (year == YearFilter.earlier) {
    return items.where((item) {
      final y = int.tryParse(item.year);
      return y != null && y <= 2021;
    }).toList();
  }
  final wanted = year.serverYear.toString();
  return items.where((item) {
    if (item.source == 'hongguo') return true; // 红果豁免年份过滤。
    if (item.year.isEmpty) return true;
    return item.year == wanted;
  }).toList();
}

/// 客户端排序（纯函数）。
///
/// - 最新：vod_time 降序（`YYYY-MM-DD HH:mm:ss` 字符串可直接比较；
///   空时间排最后）。
/// - 最热：vod_hits 降序。
/// - 红果组无时间/热度，排序时红果组整体在前（同组内保持原顺序）。
List<VodItem> sortCategoryItems(List<VodItem> items, CategorySort sort) {
  final sorted = List<VodItem>.of(items);
  int compare(VodItem a, VodItem b) {
    final aHg = a.source == 'hongguo';
    final bHg = b.source == 'hongguo';
    if (aHg != bHg) return aHg ? -1 : 1; // 红果组在前。
    switch (sort) {
      case CategorySort.latest:
        // 空时间排最后：空串与非空比较时，非空在前。
        if (a.time.isEmpty && b.time.isEmpty) return 0;
        if (a.time.isEmpty) return 1;
        if (b.time.isEmpty) return -1;
        return b.time.compareTo(a.time);
      case CategorySort.hottest:
        return b.hits.compareTo(a.hits);
    }
  }

  sorted.sort(compare);
  return sorted;
}
