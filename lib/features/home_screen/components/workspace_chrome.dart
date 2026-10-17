import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How the device workspace draws fl_panel's chrome — everything that is
/// not a pane's own content.
///
/// - **No panel header.** A pane's own header (title, actions, close) is the
///   title bar, and its `PaneGrip` / title area is what drags it, so the
///   header fl_panel would draw above a single panel is zero-height.
/// - **A tab strip only for a real group.** A group of one (what a tab
///   dragged out of a strip becomes) looks exactly like a single panel.
/// - **A visible divider** with a grip in the middle, so resizing is
///   discoverable, lighting up under the pointer.
class WorkspaceChrome extends DefaultPanelChrome {
  const WorkspaceChrome();

  @override
  double headerHeight(PanelTheme theme, SinglePanel panel) => 0;

  @override
  Widget buildHeader(BuildContext context, HeaderScope scope) =>
      const SizedBox.shrink();

  @override
  double stripHeight(PanelTheme theme, TabGroup group) =>
      group.tabs.length > 1 ? theme.stripHeight : 0;

  @override
  Widget buildStrip(BuildContext context, StripScope scope) {
    final group = scope.group;
    if (group.tabs.length < 2) return const SizedBox.shrink();
    return MetaData(
      metaData: WorkspaceStripSlot(group.id, group.tabs.length),
      child: super.buildStrip(context, scope),
    );
  }

  @override
  Widget buildDivider(BuildContext context, DividerScope scope) =>
      WorkspaceDivider(scope: scope);

  @override
  Widget buildDropPreview(BuildContext context, PanelTheme theme) => Padding(
    padding: const EdgeInsets.all(4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: theme.dropPreviewColor,
        border: Border.all(color: theme.dropPreviewBorderColor!, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

/// Marks a tab strip for the workspace's own drop hit-test — the one a drag
/// started from a pane header runs; fl_panel's chips mark themselves. A drop
/// here joins the group at the end.
@immutable
class WorkspaceStripSlot {
  const WorkspaceStripSlot(this.leafId, this.tabCount);

  final String leafId;
  final int tabCount;
}

/// The bar between two panes: drag to resize, right-click for "Equal sizes"
/// and "Swap". Its whole thickness takes the pointer; the grip in the middle
/// and the hover tint are there to make that obvious.
class WorkspaceDivider extends StatefulWidget {
  const WorkspaceDivider({super.key, required this.scope});

  final DividerScope scope;

  @override
  State<WorkspaceDivider> createState() => _WorkspaceDividerState();
}

class _WorkspaceDividerState extends State<WorkspaceDivider> {
  bool _hovered = false;
  bool _dragging = false;

  DividerScope get scope => widget.scope;

  void _start() => setState(() => _dragging = true);

  void _settle() {
    if (mounted) setState(() => _dragging = false);
    scope.onSettle();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A horizontal split lays its panes out side by side, so its dividers
    // stand upright and move along x.
    final upright = scope.geometry.axis == PanelAxis.horizontal;
    final lit = _hovered || _dragging;
    return MouseRegion(
      cursor: upright
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Track the pointer from the first pixel, not after the slop.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: upright ? (_) => _start() : null,
        onHorizontalDragUpdate: upright
            ? (details) => scope.onDrag(details.delta.dx)
            : null,
        onHorizontalDragEnd: upright ? (_) => _settle() : null,
        onHorizontalDragCancel: upright ? _settle : null,
        onVerticalDragStart: upright ? null : (_) => _start(),
        onVerticalDragUpdate: upright
            ? null
            : (details) => scope.onDrag(details.delta.dy),
        onVerticalDragEnd: upright ? null : (_) => _settle(),
        onVerticalDragCancel: upright ? null : _settle,
        onSecondaryTapUp: (details) =>
            scope.onSecondaryTap(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: lit
              ? cs.primary.withValues(alpha: 0.25)
              : cs.outlineVariant.withValues(alpha: 0.8),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: upright ? 2 : 24,
            height: upright ? 24 : 2,
            decoration: BoxDecoration(
              color: lit ? cs.primary : cs.outline.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}
