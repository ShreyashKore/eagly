import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../presentation/components/workspace_pane_scope.dart';

/// How the device workspace draws fl_panel's chrome — everything that is
/// not a pane's own content.
///
/// - **No panel header.** A pane's own header (title, actions, close) is the
///   title bar, and its `PaneGrip` / title area is what drags it, so the
///   header fl_panel would draw above a single panel is zero-height.
/// - **A tab strip only for a real group.** A group of one (what a tab
///   dragged out of a strip becomes) looks exactly like a single panel. Its
///   chips move their tabs only after [paneDragSlop], like a pane header.
/// - **A visible divider** with a grip in the middle, so resizing is
///   discoverable, lighting up under the pointer.
class const WorkspaceChrome() extends DefaultPanelChrome {
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
      child: _DeliberateDragStrip(
        scope: scope,
        builder: (context, scope) => super.buildStrip(context, scope),
      ),
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

/// Holds back the drags fl_panel's strip starts — from a chip or the strip's
/// background — until the pointer is [paneDragSlop] from where it was
/// pressed. fl_panel starts them after a mouse pan's 2 px, which a shaky click
/// on a chip reaches, and no gesture setting moves that for a mouse; so the
/// strip is handed callbacks that wait instead.
class const _DeliberateDragStrip({required this.scope, required this.builder})
    extends StatefulWidget {
  final StripScope scope;
  final Widget Function(BuildContext context, StripScope scope) builder;

  @override
  State<_DeliberateDragStrip> createState() => _DeliberateDragStripState();
}

class _DeliberateDragStripState extends State<_DeliberateDragStrip> {
  /// Built once per fl_panel callbacks object, which the host keeps across
  /// frames, so the strip still sees equal inputs and its gesture state
  /// survives a rebuild mid-press.
  late ChromeCallbacks _callbacks;

  ChromeCallbacks get _host => widget.scope.callbacks;

  /// Where the latest press went down. A pan reports where it won the
  /// arena, already some way along, so the distance is measured from here.
  Offset? _down;

  // The press under way: which chip (or strip) it is on, where it began,
  // and whether it has gone far enough to be handed to fl_panel.
  String? _tabId;
  String? _leafId;
  Offset? _origin;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _callbacks = _hold(_host);
  }

  @override
  void didUpdateWidget(_DeliberateDragStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_host, oldWidget.scope.callbacks)) {
      _callbacks = _hold(_host);
    }
  }

  ChromeCallbacks _hold(ChromeCallbacks host) => ChromeCallbacks(
    onActivate: host.onActivate,
    onClose: host.onClose,
    onCloseLeaf: host.onCloseLeaf,
    onFocusLeaf: host.onFocusLeaf,
    onDragTabStart: (tabId, global) => _press(global, tabId: tabId),
    onDragLeafStart: (leafId, global) => _press(global, leafId: leafId),
    onDragUpdate: _move,
    onDragEnd: _release,
    onDragCancel: _cancel,
    onTabSecondaryTap: host.onTabSecondaryTap,
    onStripSecondaryTap: host.onStripSecondaryTap,
    onHeaderSecondaryTap: host.onHeaderSecondaryTap,
  );

  void _press(Offset global, {String? tabId, String? leafId}) {
    _tabId = tabId;
    _leafId = leafId;
    _origin = _down ?? global;
    _dragging = false;
  }

  void _move(Offset global) {
    final origin = _origin;
    if (origin == null) return;
    if (_dragging) return _host.onDragUpdate(global);
    if ((global - origin).distance <= paneDragSlop) return;
    _dragging = true;
    // Starting hit-tests at [global] too, so no update is needed with it.
    if (_tabId case final tabId?) {
      _host.onDragTabStart(tabId, global);
    } else if (_leafId case final leafId?) {
      _host.onDragLeafStart(leafId, global);
    }
  }

  void _release() {
    if (_dragging) {
      _host.onDragEnd();
    } else if (_tabId case final tabId?) {
      // The pan took the press from the chip's tap at 2 px, so a click that
      // wobbled less than the slop lands here; it still selects the tab.
      _host.onActivate(tabId);
    }
    _reset();
  }

  void _cancel() {
    if (_dragging) _host.onDragCancel();
    _reset();
  }

  void _reset() {
    _tabId = null;
    _leafId = null;
    _origin = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final strip = widget.builder(
      context,
      StripScope(
        windowId: scope.windowId,
        theme: scope.theme,
        callbacks: _callbacks,
        decorations: scope.decorations,
        titleOf: scope.titleOf,
        focused: scope.focused,
        group: scope.group,
        scrollController: scope.scrollController,
        reveal: scope.reveal,
      ),
    );
    return Listener(
      onPointerDown: (event) => _down = event.position,
      child: strip,
    );
  }
}

/// Marks a tab strip for the workspace's own drop hit-test — the one a drag
/// started from a pane header runs; fl_panel's chips mark themselves. A drop
/// here joins the group at the end.
@immutable
class const WorkspaceStripSlot(this.leafId, this.tabCount) {
  final String leafId;
  final int tabCount;
}

/// The bar between two panes: drag to resize, right-click for "Equal sizes"
/// and "Swap". Its whole thickness takes the pointer; the grip in the middle
/// and the hover tint are there to make that obvious.
class const WorkspaceDivider({super.key, required this.scope})
    extends StatefulWidget {
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
