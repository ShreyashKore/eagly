import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One collapsible toolbar action. Rendered as a button while it fits in the
/// bar and as an entry in the overflow menu once it doesn't, so the same
/// description has to serve both: [icon] + [tooltip] in the bar, [icon] +
/// [label] in the menu.
@immutable
class ToolbarAction {
  const ToolbarAction({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onPressed,
    this.isActive = false,
    this.color,
    this.iconOverride,
    this.dividerBefore = false,
    this.barBuilder,
  });

  final IconData icon;

  /// Text in the overflow menu; also the fallback tooltip in the bar.
  final String label;

  final String? tooltip;

  /// `null` disables the action in both the bar and the menu.
  final VoidCallback? onPressed;

  /// Toggle-style actions: tints the button and shows a check in the menu.
  final bool isActive;

  final Color? color;

  /// Replaces the icon in the bar (e.g. a progress spinner). The menu always
  /// uses [icon].
  final Widget? iconOverride;

  /// Draws a group separator before this action — a vertical divider in the
  /// bar, a [PopupMenuDivider] in the menu.
  final bool dividerBefore;

  /// Renders this action in the bar, overriding the toolbar's default button
  /// (e.g. a labelled switch). The menu entry always uses [icon] / [label].
  final ToolbarActionBuilder? barBuilder;

  bool get enabled => onPressed != null;
}

/// Builds the in-bar button for an action, so a toolbar can keep its own
/// button style (see `ToolbarIconButton` in the logs feature).
typedef ToolbarActionBuilder =
    Widget Function(BuildContext context, ToolbarAction action);

/// A toolbar row that never overflows: it shows as many [actions] as fit and
/// collapses the rest — from the end of the list, so put the least important
/// ones last — into a "more" popup menu that only appears when something is
/// actually hidden.
///
/// [leading] and [trailing] widgets are always visible (navigation, the pane
/// close button); [flexible] takes whatever width is left over (a search field,
/// or `const SizedBox.shrink()` used as a spacer) and never shrinks below
/// [flexibleMinWidth] — actions collapse before it does.
class OverflowToolbar extends StatefulWidget {
  const OverflowToolbar({
    super.key,
    required this.actions,
    this.leading = const [],
    this.flexible,
    this.flexibleMinWidth = 0,
    this.trailing = const [],
    this.spacing = 4,
    this.iconSize = 20,
    this.actionBuilder,
    this.overflowIcon = Icons.more_horiz,
    this.overflowTooltip = 'More actions',
  });

  /// Collapsible actions, in display order. The last ones collapse first.
  final List<ToolbarAction> actions;

  final List<Widget> leading;

  /// Child that absorbs the leftover width, placed after [leading].
  final Widget? flexible;
  final double flexibleMinWidth;

  final List<Widget> trailing;

  /// Horizontal gap inserted between visible children.
  final double spacing;

  final double iconSize;

  /// Renders an action in the bar. Defaults to an [IconButton].
  final ToolbarActionBuilder? actionBuilder;

  final IconData overflowIcon;
  final String overflowTooltip;

  @override
  State<OverflowToolbar> createState() => _OverflowToolbarState();
}

class _OverflowToolbarState extends State<OverflowToolbar> {
  /// Written by the layout, read by the menu when it opens — no rebuild is
  /// needed for either, which is why this is a plain mutable holder.
  final _OverflowStatus _status = _OverflowStatus();

  @override
  Widget build(BuildContext context) {
    final buildAction = widget.actionBuilder ?? _defaultActionButton;
    return _ToolbarLayout(
      leadingCount: widget.leading.length,
      hasFlexible: widget.flexible != null,
      actionCount: widget.actions.length,
      flexibleMinWidth: widget.flexibleMinWidth,
      spacing: widget.spacing,
      status: _status,
      children: [
        ...widget.leading,
        if (widget.flexible != null) widget.flexible!,
        for (final action in widget.actions)
          _wrapWithDivider(
            context,
            action,
            (action.barBuilder ?? buildAction)(context, action),
          ),
        _buildOverflowButton(context),
        ...widget.trailing,
      ],
    );
  }

  Widget _wrapWithDivider(
    BuildContext context,
    ToolbarAction action,
    Widget button,
  ) {
    if (!action.dividerBefore) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
        ),
        button,
      ],
    );
  }

  Widget _defaultActionButton(BuildContext context, ToolbarAction action) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: action.tooltip ?? action.label,
      iconSize: widget.iconSize,
      color: action.isActive ? theme.colorScheme.primary : action.color,
      onPressed: action.onPressed,
      icon: action.iconOverride ?? Icon(action.icon),
    );
  }

  Widget _buildOverflowButton(BuildContext context) {
    return PopupMenuButton<ToolbarAction>(
      tooltip: widget.overflowTooltip,
      icon: Icon(widget.overflowIcon),
      iconSize: widget.iconSize,
      position: PopupMenuPosition.under,
      itemBuilder: _buildMenuItems,
      onSelected: (action) => action.onPressed?.call(),
    );
  }

  List<PopupMenuEntry<ToolbarAction>> _buildMenuItems(BuildContext context) {
    final hiddenFrom = _status.hiddenFrom;
    if (hiddenFrom < 0) return const [];

    final theme = Theme.of(context);
    final items = <PopupMenuEntry<ToolbarAction>>[];
    for (var i = hiddenFrom; i < widget.actions.length; i++) {
      final action = widget.actions[i];
      if (action.dividerBefore && items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
      final color = !action.enabled
          ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
          : action.isActive
          ? theme.colorScheme.primary
          : action.color ?? theme.colorScheme.onSurfaceVariant;
      items.add(
        PopupMenuItem<ToolbarAction>(
          value: action,
          enabled: action.enabled,
          height: 40,
          child: Row(
            children: [
              Icon(action.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(action.label, style: theme.textTheme.bodyMedium),
              ),
              if (action.isActive) ...[
                const SizedBox(width: 12),
                Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
      );
    }
    return items;
  }
}

/// Index of the first collapsed action, or -1 when everything fits. Set during
/// layout and read when the overflow menu opens.
class _OverflowStatus {
  int hiddenFrom = -1;
}

// ── Layout ────────────────────────────────────────────────────────────────

/// Children are laid out in a fixed order: [leadingCount] leading widgets, the
/// optional flexible child, [actionCount] actions, the overflow button, then
/// the trailing widgets.
class _ToolbarLayout extends MultiChildRenderObjectWidget {
  const _ToolbarLayout({
    required this.leadingCount,
    required this.hasFlexible,
    required this.actionCount,
    required this.flexibleMinWidth,
    required this.spacing,
    required this.status,
    required super.children,
  });

  final int leadingCount;
  final bool hasFlexible;
  final int actionCount;
  final double flexibleMinWidth;
  final double spacing;
  final _OverflowStatus status;

  @override
  _RenderToolbarLayout createRenderObject(BuildContext context) {
    return _RenderToolbarLayout(
      leadingCount: leadingCount,
      hasFlexible: hasFlexible,
      actionCount: actionCount,
      flexibleMinWidth: flexibleMinWidth,
      spacing: spacing,
      status: status,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderToolbarLayout renderObject,
  ) {
    renderObject
      ..leadingCount = leadingCount
      ..hasFlexible = hasFlexible
      ..actionCount = actionCount
      ..flexibleMinWidth = flexibleMinWidth
      ..spacing = spacing
      ..status = status;
  }
}

class _ToolbarParentData extends ContainerBoxParentData<RenderBox> {
  /// Collapsed actions stay in the tree but are not painted or hit-tested.
  bool visible = true;
}

class _RenderToolbarLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ToolbarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ToolbarParentData> {
  _RenderToolbarLayout({
    required int leadingCount,
    required bool hasFlexible,
    required int actionCount,
    required double flexibleMinWidth,
    required double spacing,
    required _OverflowStatus status,
  }) : _leadingCount = leadingCount,
       _hasFlexible = hasFlexible,
       _actionCount = actionCount,
       _flexibleMinWidth = flexibleMinWidth,
       _spacing = spacing,
       _status = status;

  int _leadingCount;
  set leadingCount(int value) {
    if (_leadingCount == value) return;
    _leadingCount = value;
    markNeedsLayout();
  }

  bool _hasFlexible;
  set hasFlexible(bool value) {
    if (_hasFlexible == value) return;
    _hasFlexible = value;
    markNeedsLayout();
  }

  int _actionCount;
  set actionCount(int value) {
    if (_actionCount == value) return;
    _actionCount = value;
    markNeedsLayout();
  }

  double _flexibleMinWidth;
  set flexibleMinWidth(double value) {
    if (_flexibleMinWidth == value) return;
    _flexibleMinWidth = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  _OverflowStatus _status;
  set status(_OverflowStatus value) {
    if (identical(_status, value)) return;
    _status = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ToolbarParentData) {
      child.parentData = _ToolbarParentData();
    }
  }

  int get _actionStart => _leadingCount + (_hasFlexible ? 1 : 0);
  int get _overflowIndex => _actionStart + _actionCount;

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final childConstraints = BoxConstraints(maxHeight: constraints.maxHeight);

    var fixedWidth = 0.0;
    var fixedCount = 0;
    var maxChildHeight = 0.0;

    void layoutFixed(RenderBox child) {
      child.layout(childConstraints, parentUsesSize: true);
      fixedWidth += child.size.width;
      fixedCount++;
      maxChildHeight = math.max(maxChildHeight, child.size.height);
    }

    for (var i = 0; i < _leadingCount; i++) {
      layoutFixed(children[i]);
    }
    for (var i = _overflowIndex + 1; i < children.length; i++) {
      layoutFixed(children[i]);
    }

    final overflowChild = children[_overflowIndex];
    overflowChild.layout(childConstraints, parentUsesSize: true);
    final overflowWidth = overflowChild.size.width;

    final actionWidths = <double>[];
    for (var i = 0; i < _actionCount; i++) {
      final child = children[_actionStart + i];
      child.layout(childConstraints, parentUsesSize: true);
      actionWidths.add(child.size.width);
      maxChildHeight = math.max(maxChildHeight, child.size.height);
    }

    // Width taken by everything that is always visible, plus the given number
    // of actions and (optionally) the overflow button. The flexible child
    // counts at its minimum: actions collapse before it is squeezed further.
    double widthFor(int visibleActions, bool withOverflow) {
      var total = 0.0;
      var count = fixedCount + (_hasFlexible ? 1 : 0);
      for (var i = 0; i < visibleActions; i++) {
        total += actionWidths[i];
        count++;
      }
      if (withOverflow) {
        total += overflowWidth;
        count++;
      }
      total += fixedWidth + (_hasFlexible ? _flexibleMinWidth : 0);
      return total + _spacing * math.max(0, count - 1);
    }

    final available = constraints.maxWidth;
    var visibleActions = _actionCount;
    var showOverflow = false;
    // With no actions there is nothing to collapse — the toolbar just gets
    // squeezed rather than growing an empty menu.
    if (_actionCount > 0 &&
        available.isFinite &&
        widthFor(_actionCount, false) > available) {
      showOverflow = true;
      while (visibleActions > 0 && widthFor(visibleActions, true) > available) {
        visibleActions--;
      }
    }
    _status.hiddenFrom = showOverflow ? visibleActions : -1;

    if (_hasFlexible) {
      final leftover = available.isFinite
          ? available - widthFor(visibleActions, showOverflow)
          : 0.0;
      final flexible = children[_leadingCount];
      final width = math.max(0.0, _flexibleMinWidth + leftover);
      flexible.layout(
        BoxConstraints.tightFor(width: width).enforce(childConstraints),
        parentUsesSize: true,
      );
      maxChildHeight = math.max(maxChildHeight, flexible.size.height);
    }

    for (final child in children) {
      (child.parentData! as _ToolbarParentData).visible = false;
    }

    final totalWidth = widthFor(visibleActions, showOverflow);
    size = constraints.constrain(
      Size(available.isFinite ? available : totalWidth, maxChildHeight),
    );

    var x = 0.0;
    var placedAny = false;
    void place(RenderBox child) {
      if (placedAny) x += _spacing;
      final data = child.parentData! as _ToolbarParentData;
      data.visible = true;
      data.offset = Offset(x, (size.height - child.size.height) / 2);
      x += child.size.width;
      placedAny = true;
    }

    for (var i = 0; i < _leadingCount; i++) {
      place(children[i]);
    }
    if (_hasFlexible) place(children[_leadingCount]);
    for (var i = 0; i < visibleActions; i++) {
      place(children[_actionStart + i]);
    }
    if (showOverflow) place(overflowChild);
    for (var i = _overflowIndex + 1; i < children.length; i++) {
      place(children[i]);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      total += child.getMaxIntrinsicWidth(height);
      count++;
      child = childAfter(child);
    }
    return total + _spacing * math.max(0, count - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _maxChildIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _maxChildIntrinsicHeight(width);

  double _maxChildIntrinsicHeight(double width) {
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      height = math.max(height, child.getMaxIntrinsicHeight(double.infinity));
      child = childAfter(child);
    }
    return height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final height = constraints.hasTightHeight
        ? constraints.maxHeight
        : _maxChildIntrinsicHeight(constraints.maxWidth);
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : computeMaxIntrinsicWidth(height);
    return constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ToolbarParentData;
      if (data.visible) context.paintChild(child, data.offset + offset);
      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _ToolbarParentData;
      if (data.visible) {
        final hit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (result, transformed) =>
              child!.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      if ((child.parentData! as _ToolbarParentData).visible) visitor(child);
      child = childAfter(child);
    }
  }
}
