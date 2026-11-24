library;

/// 自适应布局断点与规则（M1 地基，M2 电视端复用同一套）。
///
/// 不要在任何页面写死宽度/列数/字号：所有尺寸决策都走这里，
/// 随窗口尺寸缩放。
///
/// - 窄屏 <600（手机）：底部导航 + 2-3 列卡片
/// - 中屏 600-900（平板）：底部导航 + 3-4 列卡片
/// - 宽屏 >900（大屏/电视窗口）：左侧导航栏 + 4-6 列卡片，内容区居中限宽
import 'package:flutter/material.dart';

/// 屏幕档位。
enum ScreenSize { compact, medium, expanded }

/// 窄屏/中屏分界（手机与平板之间）。
const double kMediumBreakpoint = 600;

/// 中屏/宽屏分界（平板与大屏/电视窗口之间）。
const double kExpandedBreakpoint = 900;

/// 宽屏内容区最大宽度：再宽的窗口也不让内容无限拉伸。
const double kMaxContentWidth = 1200;

/// 按宽度取档位。
ScreenSize screenSizeOf(double width) {
  if (width < kMediumBreakpoint) return ScreenSize.compact;
  if (width < kExpandedBreakpoint) return ScreenSize.medium;
  return ScreenSize.expanded;
}

/// 海报网格列数：随宽度变，不写死。
/// <360 2列；<600 3列；<900 4列；>=900 6列。
int posterColumns(double width) {
  if (width < 360) return 2;
  if (width < kMediumBreakpoint) return 3;
  if (width < kExpandedBreakpoint) return 4;
  return 6;
}

/// 宽屏是否用左侧导航栏（NavigationRail）代替底部导航。
bool useSideNavigation(double width) => width >= kExpandedBreakpoint;

/// 标题字号随档位微调（不是固定值）。
double titleFontSize(ScreenSize size) {
  switch (size) {
    case ScreenSize.compact:
      return 15;
    case ScreenSize.medium:
      return 16;
    case ScreenSize.expanded:
      return 17;
  }
}

/// 内容区居中限宽：宽屏包一层 Center + ConstrainedBox。
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= kExpandedBreakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: child,
          ),
        );
      },
    );
  }
}
