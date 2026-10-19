import 'dart:math' as math;

import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/workspace_pane_scope.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../session/workspace_layout.dart';
import 'workspace_chrome.dart';

/// The device workspace: the open feature panes laid out the way the user
/// arranged them — side by side, stacked, or grouped into tabs — with
/// dividers to resize them and drag-and-drop to rearrange them.
///
/// A view over [WorkspaceLayout]. The layout itself is fl_panel's
/// [PanelHost], drawn through [WorkspaceChrome]; this widget adds what a
/// pane's own header needs to act as its title bar ([WorkspacePaneScope]),
/// the drag those headers start, and the label that follows the pointer
/// saying where a drop would land. See docs/WORKSPACE_LAYOUT.md.
class const WorkspaceView({
  super.key,
  required final WorkspaceLayout layout,

  /// Builds [pane]'s content. Called for every open pane, including ones
  /// behind another tab, which stay mounted (offstage) so they keep their
  /// state; a moved pane is never rebuilt from scratch either.
  required final Widget Function(BuildContext context, WorkspacePane pane)
  paneBuilder,
}) extends StatefulWidget {
  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final _hostKey = GlobalKey(debugLabel: 'workspace.host');

  /// Where the pointer is during a drag, in this view's coordinates; drives
  /// the drag label.
  final _pointer = ValueNotifier<Offset?>(null);

  late final Map<WorkspacePane, _PaneControls> _controls = {
    for (final pane in WorkspacePane.values) pane: _PaneControls(this, pane),
  };

  WorkspaceLayout get _layout => widget.layout;
  PanelController get _panels => widget.layout.panels;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void didUpdateWidget(WorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layout, widget.layout)) {
      oldWidget.layout.panels.cancelDrag();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _panels.cancelDrag();
    _pointer.dispose();
    super.dispose();
  }

  /// Escape abandons a drag, wherever it started.
  bool _handleKey(KeyEvent event) {
    if (_panels.drag == null) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    _panels.cancelDrag();
    return true;
  }

  // ── Header drags ──────────────────────────────────────────────────────
  //
  // fl_panel drags its own chips and strips. A pane header is content, out
  // of its reach, so the drag is driven here through the same controller
  // verbs, hit-testing the way the host does.

  void _startDrag(WorkspacePane pane, Offset globalPosition) {
    final source = _layout.sourceFor(pane);
    if (source == null) return;
    _panels.beginDrag(WorkspaceLayout.windowId, source);
    _updateDrag(globalPosition);
  }

  void _updateDrag(Offset globalPosition) {
    if (_panels.drag == null) return;
    final box = _hostKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    _pointer.value = local;
    final root = _layout.root;
    final layout = _panels.solver.layout(
      root,
      PanelRect(0, 0, box.size.width, box.size.height),
    );
    _panels.updateDrag(_hitAt(globalPosition, local, layout, root), layout);
  }

  DockHit _hitAt(
    Offset globalPosition,
    Offset local,
    LayoutResult layout,
    LayoutNode? root,
  ) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final slot = target.metaData;
        if (slot is WorkspaceStripSlot) {
          return DockHit.strip(slot.leafId, slot.tabCount);
        }
      }
    }
    final leaf = layout.leafAt(root, local.dx, local.dy);
    return leaf == null
        ? const DockHit.none()
        : DockHit.leaf(leaf.id, local.dx, local.dy);
  }

  // ── Building ──────────────────────────────────────────────────────────

  Widget _buildPane(BuildContext context, PanelTab tab) {
    final pane = WorkspacePane.fromId(tab.id);
    if (pane == null) return const SizedBox.shrink();
    return WorkspacePaneScope(
      controls: _controls[pane]!,
      isTabbed: _layout.isTabbed(pane),
      canMove: _layout.openPanes.length > 1,
      child: widget.paneBuilder(context, pane),
    );
  }

  PanelTheme _panelTheme(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme.labelMedium;
    return PanelTheme(
      stripHeight: context.scaled(34),
      tabMinWidth: 110,
      stripColor: cs.surfaceContainerHigh,
      // The selected chip runs into the pane header below it.
      activeTabColor: cs.surfaceContainerHighest,
      dividerColor: cs.outlineVariant,
      textStyle: text?.copyWith(color: cs.onSurfaceVariant),
      activeTextStyle: text?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
      ),
      dropPreviewColor: cs.primary.withValues(alpha: 0.16),
      dropPreviewBorderColor: cs.primary,
    );
  }

  /// fl_panel's own right-click menus (tab chips, strips, dividers), in the
  /// app's words, plus a way back to the default arrangement from each.
  List<PanelMenuEntry> _menuEntries(
    PanelMenuRequest request,
    List<PanelMenuEntry> defaults,
  ) => [
    for (final entry in defaults)
      switch (entry.id) {
        PanelMenuEntryId.equalise => entry.copyWith(label: 'Equal sizes'),
        _ => entry,
      },
    const PanelMenuEntry.separator(),
    PanelMenuEntry(
      label: 'Reset layout',
      icon: Icons.view_column_outlined,
      onSelected: _layout.isSideBySide ? null : _layout.reset,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _layout.viewportWidth = constraints.maxWidth;
        return Listener(
          // Drags fl_panel starts (chips, strips) report their pointer only
          // to fl_panel; the label still has to follow it.
          onPointerMove: (event) {
            if (_panels.drag != null) _pointer.value = event.localPosition;
          },
          child: Stack(
            // Fill the constraints even when they are loose; the hidden drag
            // label must not decide the workspace's size.
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: PanelHost(
                  key: _hostKey,
                  controller: _panels,
                  windowId: WorkspaceLayout.windowId,
                  contentBuilder: _buildPane,
                  titleOf: (tab) =>
                      WorkspacePane.fromId(tab.id)?.label ?? tab.id,
                  theme: _panelTheme(context),
                  chrome: const WorkspaceChrome(),
                  decorations: PanelDecorations(
                    tabLeading: (context, tab) {
                      final pane = WorkspacePane.fromId(tab.id);
                      return pane == null
                          ? null
                          : Icon(pane.icon, size: context.scaled(15));
                    },
                  ),
                  contextMenus: PanelMenus(build: _menuEntries),
                ),
              ),
              _DragLabel(
                layout: _layout,
                pointer: _pointer,
                bounds: constraints.biggest,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One pane's [PaneControls], kept for the life of the view so a pane's
/// [WorkspacePaneScope] compares equal from frame to frame.
class _PaneControls(final _WorkspaceViewState _view, final WorkspacePane pane)
    implements PaneControls {
  WorkspaceLayout get _layout => _view._layout;

  @override
  String get title => pane.label;

  @override
  void startDrag(Offset globalPosition) =>
      _view._startDrag(pane, globalPosition);

  @override
  void updateDrag(Offset globalPosition) => _view._updateDrag(globalPosition);

  @override
  void endDrag() => _view._panels.commitDrag();

  @override
  void cancelDrag() => _view._panels.cancelDrag();

  @override
  List<PaneMenuItem> menuItems() {
    final layout = _layout;
    final group = layout.groupOf(pane);
    final others = [
      for (final other in WorkspacePane.values)
        if (other != pane && layout.isOpen(other) && !group.contains(other))
          other,
    ];
    return [
      PaneMenuItem(
        label: 'Move to',
        icon: Icons.open_with,
        children: [
          for (final (side, label, icon) in const [
            (DockSide.left, 'Left side', Icons.arrow_back),
            (DockSide.right, 'Right side', Icons.arrow_forward),
            (DockSide.top, 'Top', Icons.arrow_upward),
            (DockSide.bottom, 'Bottom', Icons.arrow_downward),
          ])
            PaneMenuItem(
              label: label,
              icon: icon,
              onSelected: layout.canMoveToEdge(pane, side)
                  ? () => layout.moveToEdge(pane, side)
                  : null,
            ),
        ],
      ),
      if (others.isNotEmpty)
        PaneMenuItem(
          label: 'Group as tabs with',
          icon: Icons.tab_outlined,
          children: [
            for (final other in others)
              PaneMenuItem(
                label: other.label,
                icon: other.icon,
                onSelected: layout.canStackWith(pane, other)
                    ? () => layout.stackWith(pane, other)
                    : null,
              ),
          ],
        ),
      PaneMenuItem(
        label: 'Reset layout',
        icon: Icons.view_column_outlined,
        dividerBefore: true,
        onSelected: layout.isSideBySide ? null : layout.reset,
      ),
    ];
  }
}

/// The label that follows the pointer during a drag: what is moving and
/// where it would land if dropped now — the words for the shaded preview.
class const _DragLabel({
  required final WorkspaceLayout layout,
  required final ValueListenable<Offset?> pointer,
  required final Size bounds,
}) extends StatelessWidget {
  static const double _maxWidth = 280;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([layout.panels, pointer]),
      builder: (context, _) {
        final drag = layout.panels.drag;
        final at = pointer.value;
        if (drag == null ||
            at == null ||
            drag.windowId != WorkspaceLayout.windowId) {
          return const SizedBox.shrink();
        }
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final moving = _movingPanes(drag.source);
        return Positioned(
          left: math.max(0, math.min(at.dx + 16, bounds.width - _maxWidth)),
          top: math.max(0, math.min(at.dy + 16, bounds.height - 64)),
          child: IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Material(
                key: const ValueKey('workspace.dragLabel'),
                elevation: 6,
                color: cs.inverseSurface,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (moving.length == 1) ...[
                            Icon(
                              moving.single.icon,
                              size: 16,
                              color: cs.onInverseSurface,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              moving.map((pane) => pane.label).join(' + '),
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelLarge?.copyWith(
                                color: cs.onInverseSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hint(drag.candidate),
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onInverseSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<WorkspacePane> _movingPanes(DockSource source) {
    final ids = switch (source) {
      DockTabSource(:final tabId) => [tabId],
      DockLeafSource(:final leafId) => switch (layout.root?.find(leafId)) {
        LeafNode(:final tabs) => [for (final tab in tabs) tab.id],
        _ => const <String>[],
      },
      DockFreshSource(:final tabs) => [for (final tab in tabs) tab.id],
    };
    return [
      for (final id in ids)
        if (WorkspacePane.fromId(id) case final pane?) pane,
    ];
  }

  String _hint(DockCandidate? candidate) {
    if (candidate == null) {
      return 'Drop on a pane to place it beside or with it';
    }
    return switch (candidate.target) {
      DockJoin(:final leafId) => 'Group as tabs with ${_nameOf(leafId)}',
      DockSplit(:final nodeId, :final side) => switch (side) {
        DockSide.left => 'Place left of ${_nameOf(nodeId)}',
        DockSide.right => 'Place right of ${_nameOf(nodeId)}',
        DockSide.top => 'Place above ${_nameOf(nodeId)}',
        DockSide.bottom => 'Place below ${_nameOf(nodeId)}',
      },
      DockRoot(:final side) => switch (side) {
        DockSide.left => 'Place along the left edge',
        DockSide.right => 'Place along the right edge',
        DockSide.top => 'Place along the top',
        DockSide.bottom => 'Place along the bottom',
      },
    };
  }

  /// The pane showing in [nodeId] — the one the user is pointing at.
  String _nameOf(String nodeId) {
    final node = layout.root?.find(nodeId);
    final tab = switch (node) {
      LeafNode(:final activeTab) => activeTab,
      SplitNode() => node.tabs.firstOrNull,
      null => null,
    };
    return tab == null ? 'this pane' : WorkspacePane.fromId(tab.id)!.label;
  }
}

/// The rail's icon for each pane, for tab chips and the drag label.
extension WorkspacePaneIcon on WorkspacePane {
  IconData get icon => switch (this) {
    WorkspacePane.logs => Icons.article_outlined,
    WorkspacePane.mirror => Icons.mobile_screen_share,
    WorkspacePane.crashReports => Icons.bug_report_outlined,
    WorkspacePane.files => Icons.folder_outlined,
    WorkspacePane.apps => Icons.apps_outlined,
    WorkspacePane.utilities => Icons.handyman_outlined,
    WorkspacePane.terminal => Icons.terminal_outlined,
    WorkspacePane.network => Icons.http,
  };
}
