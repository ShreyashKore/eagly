import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';

/// What the device workspace hands each feature pane it hosts, for the
/// pane's header to use. See docs/WORKSPACE_LAYOUT.md.
///
/// Headers stay ignorant of the layout: they put a [PaneGrip] first,
/// optionally wrap their title area in a [PaneDragArea], and ask
/// [showsOwnTitle] / [showsOwnClose] whether a tab chip already shows those.
/// Outside a workspace (a test, the imported-logs screen) there is no scope,
/// the grip draws nothing and the header looks as it always did.
class WorkspacePaneScope extends InheritedWidget {
  const WorkspacePaneScope({
    super.key,
    required this.controls,
    required this.isTabbed,
    required this.canMove,
    required super.child,
  });

  /// The pane's moves. One object per pane for the life of the workspace,
  /// so it can be compared by identity.
  final PaneControls controls;

  /// The pane shares a tab strip, whose chip shows its title and close
  /// button — the header should not repeat them.
  final bool isTabbed;

  /// Another pane is open, so there is somewhere to move this one to.
  final bool canMove;

  /// Whether the header should lead with a [PaneGrip]: there is somewhere to
  /// move the pane, and no tab chip already serving as its handle.
  bool get showsGrip => canMove && !isTabbed;

  static WorkspacePaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspacePaneScope>();

  /// [showsGrip] for the pane [context] is in; false outside a workspace.
  static bool showsGripIn(BuildContext context) =>
      maybeOf(context)?.showsGrip ?? false;

  /// Whether a pane header should draw its own title.
  static bool showsOwnTitle(BuildContext context) =>
      !(maybeOf(context)?.isTabbed ?? false);

  /// Whether a pane header should draw its own close button.
  static bool showsOwnClose(BuildContext context) =>
      !(maybeOf(context)?.isTabbed ?? false);

  @override
  bool updateShouldNotify(WorkspacePaneScope oldWidget) =>
      !identical(oldWidget.controls, controls) ||
      oldWidget.isTabbed != isTabbed ||
      oldWidget.canMove != canMove;
}

/// The moves a hosted pane offers its header. Positions are global.
abstract interface class PaneControls {
  /// The pane's name, for the grip's tooltip.
  String get title;

  void startDrag(Offset globalPosition);
  void updateDrag(Offset globalPosition);

  /// Drops the pane where the drag is pointing, if anywhere.
  void endDrag();
  void cancelDrag();

  /// The grip's menu, built when it opens so it reflects the layout then.
  List<PaneMenuItem> menuItems();
}

/// One entry of a pane's layout menu: an action, or a submenu when
/// [children] is non-empty. A null [onSelected] greys the action out.
@immutable
class PaneMenuItem {
  const PaneMenuItem({
    required this.label,
    this.icon,
    this.onSelected,
    this.children = const [],
    this.dividerBefore = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onSelected;
  final List<PaneMenuItem> children;

  /// Starts a new group in the menu.
  final bool dividerBefore;

  bool get isSubmenu => children.isNotEmpty;
}

/// The handle a pane is moved by, placed first in its header. Dragging it
/// docks the pane elsewhere — beside another pane, along an edge, or into
/// another pane's tab group — and clicking it (or right-clicking) offers the
/// same moves as a menu, for anyone who doesn't drag. Draws nothing outside
/// a workspace, while the pane is the only one open, or while it sits in a
/// tab group, whose chip is then its handle (see
/// [WorkspacePaneScope.showsGrip]).
class PaneGrip extends StatefulWidget {
  const PaneGrip({super.key, this.iconSize = 18});

  final double iconSize;

  @override
  State<PaneGrip> createState() => _PaneGripState();
}

class _PaneGripState extends State<PaneGrip> {
  final _menu = MenuController();
  List<PaneMenuItem> _items = const [];

  void _openMenu(PaneControls controls) {
    setState(() => _items = controls.menuItems());
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final scope = WorkspacePaneScope.maybeOf(context);
    if (scope == null || !scope.showsGrip) return const SizedBox.shrink();
    final controls = scope.controls;
    return PaneDragArea(
      child: GestureDetector(
        onSecondaryTap: () => _openMenu(controls),
        child: MenuAnchor(
          controller: _menu,
          menuChildren: _buildMenuChildren(_items),
          child: AppIconButton(
            icon: Icons.drag_indicator,
            iconSize: widget.iconSize,
            padding: 4,
            mouseCursor: SystemMouseCursors.grab,
            tooltip:
                'Drag to move ${controls.title} · click for layout options',
            onPressed: () => _menu.isOpen ? _menu.close() : _openMenu(controls),
          ),
        ),
      ),
    );
  }

  static List<Widget> _buildMenuChildren(List<PaneMenuItem> items) => [
    for (final item in items) ...[
      if (item.dividerBefore && !identical(item, items.first))
        const Divider(height: 8),
      if (item.isSubmenu)
        SubmenuButton(
          leadingIcon: item.icon == null ? null : Icon(item.icon, size: 18),
          menuChildren: _buildMenuChildren(item.children),
          child: Text(item.label),
        )
      else
        MenuItemButton(
          leadingIcon: item.icon == null ? null : Icon(item.icon, size: 18),
          onPressed: item.onSelected,
          child: Text(item.label),
        ),
    ],
  ];
}

/// Makes [child] a handle that moves the pane it sits in — the grip, or the
/// title area of a pane header (the way a window is moved by its title
/// bar). Inert outside a workspace or while the pane is alone.
class PaneDragArea extends StatelessWidget {
  const PaneDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspacePaneScope.maybeOf(context);
    if (scope == null || !scope.canMove) return child;
    final controls = scope.controls;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _PaneDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_PaneDragRecognizer>(
              () => _PaneDragRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..onStart = ((details) =>
                    controls.startDrag(details.globalPosition))
                ..onUpdate = ((details) =>
                    controls.updateDrag(details.globalPosition))
                ..onEnd = ((_) => controls.endDrag())
                ..onCancel = controls.cancelDrag,
            ),
      },
      child: child,
    );
  }
}

/// A pan that needs a deliberate move to begin. A mouse pan normally wins
/// the gesture arena after 2 px, which turns a slightly shaky click on the
/// grip into a drag that goes nowhere, instead of opening its menu.
class _PaneDragRecognizer extends PanGestureRecognizer {
  _PaneDragRecognizer({super.debugOwner});

  static const double _slop = 6;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      math.max(_slop, computePanSlop(pointerDeviceKind, gestureSettings));
}
