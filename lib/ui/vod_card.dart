import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../core/config.dart';
import 'responsive.dart';

/// 一影片一卡：海报 + 标题 + 年份/类型/集数。
/// 首页、搜索、分类、详情相关推荐共用；点卡回调由调用方给
/// （一般是进详情页）。
class VodCard extends StatelessWidget {
  const VodCard({
    super.key,
    required this.item,
    required this.onSelect,
    this.autofocus = false,
  });

  final VodItem item;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      child: Card(
        key: ValueKey('vod-card-${item.id}'),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                displayPosterUrl(item.pic),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie_outlined),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleFontSize(screenSizeOf(width)),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 副标题：年份 / 类型 / 集数，有什么显示什么。
  String get _subtitle {
    final parts = <String>[];
    if (item.year.isNotEmpty) parts.add(item.year);
    if (item.typeName.isNotEmpty) parts.add(item.typeName);
    if (item.remarks.isNotEmpty) parts.add(item.remarks);
    return parts.join(' · ');
  }
}

/// 卡片网格 delegate：列数随宽度变（responsive.dart），不写死。
/// 滚动网格（首页/分类）与内嵌网格（搜索结果/相关推荐）共用。
SliverGridDelegateWithFixedCrossAxisCount vodGridDelegate(double width) {
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: posterColumns(width),
    childAspectRatio: 0.62,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
  );
}

/// 卡片网格：列数随宽度变（responsive.dart），不写死。
class VodCardGrid extends StatelessWidget {
  const VodCardGrid({
    super.key,
    required this.items,
    required this.onSelect,
    this.gridKey,
  });

  final List<VodItem> items;
  final ValueChanged<VodItem> onSelect;

  /// 传给内层 GridView 的 key（测试按 key 找网格）。
  final Key? gridKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          key: gridKey,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: vodGridDelegate(constraints.maxWidth),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return VodCard(
              item: item,
              autofocus: index == 0,
              onSelect: () => onSelect(item),
            );
          },
        );
      },
    );
  }
}
