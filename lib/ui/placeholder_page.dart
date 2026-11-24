import 'package:flutter/material.dart';

/// M1 占位页：分类/搜索/追剧/我的的完整 UI 是写页面子代理的任务，
/// 这里只放占位，等后续接手。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('$title即将推出', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
