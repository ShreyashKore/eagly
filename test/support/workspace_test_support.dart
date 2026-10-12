import 'package:fl_panel/fl_panel.dart';

/// The arrangement as a short string: `row(…)` / `column(…)` for splits, a
/// pane id for a pane on its own, `tabs(…)` for a group with the selected
/// tab starred.
String describe(LayoutNode? node) => switch (node) {
  null => '-',
  SplitNode(:final axis, :final children) =>
    '${axis == PanelAxis.horizontal ? 'row' : 'column'}'
        '(${children.map(describe).join(', ')})',
  LeafNode(:final tabs) when tabs.length == 1 => tabs.single.id,
  LeafNode(:final tabs, :final activeTab) =>
    'tabs(${tabs.map((t) => t.id == activeTab?.id ? '*${t.id}' : t.id).join(', ')})',
};
