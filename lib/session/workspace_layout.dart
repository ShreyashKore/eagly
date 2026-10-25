import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/foundation.dart';

import '../services/preferences_service.dart';

/// A feature pane of the device workspace: one per rail destination that
/// opens beside the others. Home is a separate view, not a pane.
///
/// The sizes are all the layout knows about a pane's content.
/// [preferredWidth] is the share a pane gets when it opens along the right
/// edge. [minWidth] and [minHeight] are hard floors the solver keeps unless
/// the window is too small for every floor at once. Keep the floors modest:
/// a divider between two panes already at their floors cannot move.
enum WorkspacePane(
  final String label, {
  required final double preferredWidth,
  required final double minWidth,
}) {
  logs('Logs', preferredWidth: 600, minWidth: 260),
  mirror('Mirror', preferredWidth: 340, minWidth: 200),
  crashReports('Crash Reports', preferredWidth: 360, minWidth: 240),
  files('Files', preferredWidth: 600, minWidth: 260),
  apps('Apps', preferredWidth: 420, minWidth: 240),
  utilities('Utilities', preferredWidth: 420, minWidth: 240),
  terminal('Terminal', preferredWidth: 520, minWidth: 240),
  network('Network', preferredWidth: 560, minWidth: 260),
  layoutInspector('Layout', preferredWidth: 720, minWidth: 320);

  double get minHeight => 140;

  /// The id of this pane's tab in the layout tree, and in a saved layout.
  /// Renaming a value orphans its saved placement, nothing worse.
  String get id => name;

  /// The pane a layout tab stands for, or null for one this build does not
  /// know (a saved layout from another version).
  static WorkspacePane? fromId(String id) => values.asNameMap()[id];

  /// The layout tab standing for this pane. Built from the enum every time,
  /// never read back from a saved layout, so changing a floor here applies
  /// to remembered placements too.
  PanelTab get tab =>
      PanelTab(id: id, contentId: id, minWidth: minWidth, minHeight: minHeight);
}

/// The arrangement of one device's feature panes: which are open, and how
/// they are split, stacked and grouped into tabs.
///
/// A thin, Eagly-specific layer over fl_panel's [PanelController]
/// ([panels]), which owns the tree and every edit of it — see
/// docs/WORKSPACE_LAYOUT.md. On top of it this adds:
///
/// - **Which panes are open** ([openPanes]). Listeners hear only about
///   changes to that set — never a divider drag or a tab switch, which the
///   view gets from [panels] directly.
/// - **Where a pane opens** ([show]): where it stood last time, relative to
///   whatever is open now (see [WorkspaceLayoutMemory]); otherwise along the
///   right edge at its preferred width.
/// - **Arrangement verbs** for menus and the command palette: [moveToEdge],
///   [stackWith], [reset]. Taking a tab back out of its group is fl_panel's
///   own (drag its chip, or the chip's Split menu).
class WorkspaceLayout({WorkspaceLayoutMemory? memory}) extends ChangeNotifier {
  this : memory = memory ?? WorkspaceLayoutMemory() {
    panels.onSettled = _remember;
    panels.addListener(_handlePanelsChanged);
  }

  /// The one fl_panel window the workspace draws.
  static const windowId = 'workspace';

  /// The gap between two split panes, which is also the divider's grab area.
  static const double dividerThickness = 8;

  /// Where placements are remembered. The session manager hands every
  /// device's workspace the same one, so a pane opens where the user last put
  /// it whichever device they are on.
  final WorkspaceLayoutMemory memory;

  final PanelController panels = PanelController(
    solver: const PanelSolver(dividerThickness: dividerThickness),
  );

  /// The workspace's last laid-out width, reported by the view; sizes a pane
  /// opening along the right edge. Null until the workspace has been shown.
  double? viewportWidth;

  Set<WorkspacePane> _open = const {};

  /// This session's remembered arrangement: [memory]'s, read on first use,
  /// then kept current here so a second device's session writing to
  /// [memory] cannot reshuffle where this one's panes come back.
  LayoutNode? _arrangement;
  bool _arrangementLoaded = false;

  LayoutNode? get root => panels.rootOf(windowId);

  Set<WorkspacePane> get openPanes => _open;
  bool get isEmpty => _open.isEmpty;
  bool isOpen(WorkspacePane pane) => _open.contains(pane);

  /// Whether [pane] is open and in front: alone in its area, or the
  /// selected tab of its group.
  bool isShown(WorkspacePane pane) =>
      root?.leafOf(pane.id)?.activeTab?.id == pane.id;

  /// Whether [pane] shares a tab group with another pane.
  bool isTabbed(WorkspacePane pane) =>
      (root?.leafOf(pane.id)?.tabs.length ?? 0) > 1;

  /// The panes sharing [pane]'s tab group, [pane] included, in tab order.
  List<WorkspacePane> groupOf(WorkspacePane pane) => [
    for (final tab in root?.leafOf(pane.id)?.tabs ?? const <PanelTab>[])
      if (WorkspacePane.fromId(tab.id) case final member?) member,
  ];

  // ── Opening and closing ───────────────────────────────────────────────

  /// Opens [pane] where it stood last time — or along the right edge — or,
  /// when it is already open, brings its tab to the front.
  void show(WorkspacePane pane) {
    final root = this.root;
    if (root?.leafOf(pane.id) != null) {
      panels.activate(pane.id);
      return;
    }
    final placed =
        _placeAsRemembered(root, pane) ?? _placeAlongRightEdge(root, pane);
    _replaceRoot(placed);
  }

  /// Closes [pane]. Its neighbours take its room, and its place is
  /// remembered for the next [show].
  void hide(WorkspacePane pane) {
    final root = this.root;
    if (root?.leafOf(pane.id) == null) return;
    _replaceRoot(LayoutTree.removeTab(root, pane.id));
  }

  /// Whether the open panes stand as [saved] has them once cut down to the
  /// panes in [available] — what [applySaved] would lay out.
  bool matchesSaved(LayoutNode saved, Set<WorkspacePane> available) {
    final kept = WorkspaceArrangement.project(saved, {
      for (final pane in available) pane.id,
    });
    return WorkspaceArrangement.sameShape(LayoutTree.normalise(kept), root);
  }

  /// Replaces whatever is open with [saved] cut down to the panes in
  /// [available] — how a device opens with the saved layout, leaving out
  /// the panes it cannot host. Returns the panes now open; leaves the
  /// workspace alone and returns nothing when none of [saved]'s panes is
  /// available.
  Set<WorkspacePane> applySaved(
    LayoutNode saved,
    Set<WorkspacePane> available,
  ) {
    final kept = WorkspaceArrangement.project(saved, {
      for (final pane in available) pane.id,
    });
    if (kept == null) return const {};
    _replaceRoot(kept);
    return _open;
  }

  /// A drag in progress holds the tree its drop was computed on; dropping
  /// that after a pane came or went would undo the change, so it ends here.
  void _replaceRoot(LayoutNode? root) {
    panels
      ..cancelDrag()
      ..setRoot(windowId, root);
  }

  // ── Arranging ─────────────────────────────────────────────────────────

  /// What a drag or a move of [pane] picks up: its whole area when the pane
  /// stands alone, otherwise just its tab, out of the group.
  DockSource? sourceFor(WorkspacePane pane) {
    final leaf = root?.leafOf(pane.id);
    if (leaf == null) return null;
    return leaf.tabs.length == 1
        ? DockSource.leaf(leaf.id)
        : DockSource.tab(pane.id);
  }

  bool canMoveToEdge(WorkspacePane pane, DockSide side) =>
      _can(pane, DockTarget.root(side, form: SurfaceForm.single));

  /// Moves [pane] to [side] of the workspace, spanning its whole height (or
  /// width), as an area of its own.
  bool moveToEdge(WorkspacePane pane, DockSide side) =>
      _dock(pane, DockTarget.root(side, form: SurfaceForm.single));

  bool canStackWith(WorkspacePane pane, WorkspacePane other) {
    final leaf = root?.leafOf(other.id);
    return leaf != null && _can(pane, DockTarget.join(leaf.id));
  }

  /// Puts [pane] in [other]'s tab group — making one when [other] stands
  /// alone — as the selected tab.
  bool stackWith(WorkspacePane pane, WorkspacePane other) {
    final leaf = root?.leafOf(other.id);
    return leaf != null && _dock(pane, DockTarget.join(leaf.id));
  }

  /// Whether the open panes stand side by side, left to right in rail
  /// order, each in an area of its own — what [reset] produces. Sizes are
  /// not compared.
  bool get isSideBySide {
    final root = this.root;
    final List<LayoutNode> areas = switch (root) {
      null => const [],
      SplitNode(axis: PanelAxis.horizontal) => root.children,
      SplitNode() => const [],
      LeafNode() => [root],
    };
    if (areas.length != _open.length) return false;
    final order = [
      for (final pane in WorkspacePane.values)
        if (_open.contains(pane)) pane.id,
    ];
    for (var i = 0; i < areas.length; i++) {
      final area = areas[i];
      if (area is! LeafNode || area.tabs.length != 1) return false;
      if (area.tabs.single.id != order[i]) return false;
    }
    return true;
  }

  /// Puts the open panes back side by side, in rail order, at their
  /// preferred widths, and forgets every remembered placement.
  void reset() {
    _arrangement = null;
    _arrangementLoaded = true;
    memory.arrangement = null;
    final panes = [
      for (final pane in WorkspacePane.values)
        if (_open.contains(pane)) pane,
    ];
    if (panes.isEmpty) return;
    _replaceRoot(
      panes.length == 1
          ? SinglePanel(id: panels.newId(), tab: panes.single.tab)
          : SplitNode(
              id: panels.newId(),
              axis: PanelAxis.horizontal,
              children: [
                for (final pane in panes)
                  SinglePanel(id: panels.newId(), tab: pane.tab),
              ],
              sizes: [
                for (final pane in panes) PanelExtent.flex(pane.preferredWidth),
              ],
            ),
    );
  }

  bool _can(WorkspacePane pane, DockTarget target) {
    final source = sourceFor(pane);
    return source != null && panels.canDock(windowId, source, target);
  }

  bool _dock(WorkspacePane pane, DockTarget target) {
    final source = sourceFor(pane);
    return source != null && panels.dock(windowId, source, target);
  }

  // ── Placement ─────────────────────────────────────────────────────────

  LayoutNode? get _rememberedArrangement {
    if (!_arrangementLoaded) {
      _arrangementLoaded = true;
      _arrangement = memory.arrangement;
    }
    return _arrangement;
  }

  LayoutNode? _placeAsRemembered(LayoutNode? root, WorkspacePane pane) {
    final arrangement = _rememberedArrangement;
    if (arrangement == null || root == null) return null;
    return WorkspaceArrangement.placeAsIn(
      arrangement,
      root,
      pane.tab,
      newId: panels.newId,
    );
  }

  LayoutNode _placeAlongRightEdge(LayoutNode? root, WorkspacePane pane) {
    if (root == null) return SinglePanel(id: panels.newId(), tab: pane.tab);
    final placed = LayoutTree.dock(
      root,
      DockSource.fresh([pane.tab]),
      const DockTarget.root(DockSide.right, form: SurfaceForm.single),
      newId: panels.newId,
    );
    if (placed == null) return root;
    final width = viewportWidth;
    final share = width == null || width <= 0
        ? 1 / (_open.length + 1)
        : pane.preferredWidth / width;
    return WorkspaceArrangement.withShare(
      placed,
      pane.id,
      share.clamp(0.2, 0.5),
    );
  }

  /// After every settled change — a drop, an open or close, a released
  /// divider — fold the live tree into the remembered arrangement and save.
  void _remember() {
    final merged = WorkspaceArrangement.merge(root, _rememberedArrangement);
    _arrangement = merged;
    memory.arrangement = merged;
  }

  void _handlePanelsChanged() {
    final open = <WorkspacePane>{
      for (final tab in root?.tabs ?? const <PanelTab>[])
        if (WorkspacePane.fromId(tab.id) case final pane?) pane,
    };
    if (setEquals(open, _open)) return;
    _open = Set.unmodifiable(open);
    notifyListeners();
  }

  @override
  void dispose() {
    panels.removeListener(_handlePanelsChanged);
    panels.dispose();
    super.dispose();
  }
}

/// The arrangement the workspace remembers: one layout tree holding every
/// pane the user has placed, open or closed, where each last stood.
///
/// [WorkspaceLayout] rewrites it after every settled change and reads it to
/// decide where a reopened pane goes. [WorkspaceLayoutMemory.persisted]
/// keeps it in preferences, so placement also survives a restart.
class WorkspaceLayoutMemory() {
  /// Kept in memory only — what tests and stand-alone sessions use.
  this;

  /// Backed by [PreferencesService]. Read lazily: nothing touches the store
  /// until a pane first opens.
  factory persisted() = _PersistedWorkspaceLayoutMemory;

  /// The remembered arrangement; null when nothing is remembered.
  LayoutNode? arrangement;

  /// The layout the user saved for every device to open with (View → Save
  /// Layout); null when none is saved. Unlike [arrangement] it changes only
  /// when the user saves or clears it.
  LayoutNode? saved;

  /// [arrangement] as JSON for storage; null for none.
  static Map<String, Object?>? encode(LayoutNode? arrangement) =>
      arrangement == null
      ? null
      : PanelJson.encodeWorkspace(
          PanelWorkspace(
            windows: [
              PanelWindow(id: WorkspaceLayout.windowId, root: arrangement),
            ],
          ),
        );

  /// Reads what [encode] wrote. Anything unreadable — a newer format, a
  /// hand-edited file, panes this build does not know — reads as nothing
  /// remembered (or the panes it does know) rather than an error: a bad
  /// preference must never keep a pane from opening.
  static LayoutNode? decode(Map<String, Object?>? json) {
    if (json == null) return null;
    final seen = <String>{};
    try {
      final workspace = PanelJson.decodeWorkspace(
        json,
        resolve: (tab) {
          final pane = WorkspacePane.fromId(tab.id);
          if (pane == null || !seen.add(pane.id)) return null;
          return pane.tab;
        },
      );
      return workspace.window(WorkspaceLayout.windowId)?.root;
    } catch (_) {
      return null;
    }
  }
}

class _PersistedWorkspaceLayoutMemory extends WorkspaceLayoutMemory {
  bool _loaded = false;
  bool _savedLoaded = false;

  @override
  LayoutNode? get saved {
    if (!_savedLoaded) {
      _savedLoaded = true;
      super.saved = WorkspaceLayoutMemory.decode(
        PreferencesService.savedWorkspaceLayout,
      );
    }
    return super.saved;
  }

  @override
  set saved(LayoutNode? value) {
    _savedLoaded = true;
    super.saved = value;
    PreferencesService.savedWorkspaceLayout = WorkspaceLayoutMemory.encode(
      value,
    );
  }

  @override
  LayoutNode? get arrangement {
    if (!_loaded) {
      _loaded = true;
      super.arrangement = WorkspaceLayoutMemory.decode(
        PreferencesService.workspaceLayout,
      );
    }
    return super.arrangement;
  }

  @override
  set arrangement(LayoutNode? value) {
    _loaded = true;
    super.arrangement = value;
    PreferencesService.workspaceLayout = WorkspaceLayoutMemory.encode(value);
  }
}

/// The tree surgery behind remembered placement — pure functions over
/// fl_panel trees, kept apart from [WorkspaceLayout] so they can be tested
/// on their own.
///
/// A placement is remembered as a whole tree (the *arrangement*) rather than
/// as per-pane coordinates. To put pane P back, the arrangement is cut down
/// to the panes open now plus P, and P's place in that smaller tree — beside
/// which neighbours, on which side, at what share, or in whose tab group —
/// is replayed on the live tree. Cutting down first is what makes the
/// neighbours always ones that are open.
abstract final class WorkspaceArrangement {
  /// [live] with [tab] put back where [arrangement] has it, relative to the
  /// panes [live] holds; null when [arrangement] doesn't know the pane, or
  /// [live] is empty and there is nothing to place it beside.
  static LayoutNode? placeAsIn(
    LayoutNode arrangement,
    LayoutNode? live,
    PanelTab tab, {
    String Function() newId = PanelIds.next,
  }) {
    if (live == null || arrangement.leafOf(tab.id) == null) return null;
    final keep = {for (final t in live.tabs) t.id, tab.id};
    final projected = project(arrangement, keep);
    if (projected == null) return null;
    final leaf = projected.leafOf(tab.id)!;

    // Shared a tab group: join the group of the first mate still open.
    if (leaf.tabs.length > 1) {
      for (final mate in leaf.tabs) {
        if (mate.id == tab.id) continue;
        final target = live.leafOf(mate.id);
        if (target == null) continue;
        return LayoutTree.dock(
          live,
          DockSource.fresh([tab]),
          DockTarget.join(target.id),
          newId: newId,
        );
      }
      return null;
    }

    // Stood beside a neighbour: split beside the smallest live subtree that
    // holds every pane of that neighbour, on the same side, at the same
    // share of the two.
    final parent = projected.parentOf(leaf.id);
    if (parent == null) return null;
    final index = parent.children.indexWhere((child) => child.id == leaf.id);
    final after = index > 0;
    final other = after ? index - 1 : index + 1;
    final neighbours = {for (final t in parent.children[other].tabs) t.id};
    final side = switch ((parent.axis, after)) {
      (PanelAxis.horizontal, true) => DockSide.right,
      (PanelAxis.horizontal, false) => DockSide.left,
      (PanelAxis.vertical, true) => DockSide.bottom,
      (PanelAxis.vertical, false) => DockSide.top,
    };
    final target = _smallestHolding(live, neighbours);
    final placed = LayoutTree.dock(
      live,
      DockSource.fresh([tab]),
      DockTarget.split(target.id, side, form: SurfaceForm.single),
      newId: newId,
    );
    if (placed == null) return null;
    return withShare(
      placed,
      tab.id,
      _share(parent.sizes[index], parent.sizes[other]),
      besideId: target.id,
    );
  }

  /// [live] grown with every pane [arrangement] remembers that [live] lacks,
  /// each put back where [arrangement] has it — so closing a pane keeps its
  /// place, and an arrangement made on one device survives another's. An
  /// empty [live] leaves [arrangement] as it is.
  static LayoutNode? merge(LayoutNode? live, LayoutNode? arrangement) {
    if (arrangement == null || live == null) return live ?? arrangement;
    var result = live;
    for (final tab in arrangement.tabs) {
      if (result.leafOf(tab.id) != null) continue;
      result = placeAsIn(arrangement, result, tab) ?? result;
    }
    return result;
  }

  /// Whether [a] and [b] lay the same panes out the same way: the same
  /// splits on the same axes at the same shares, and the same tabs in each
  /// area, in order. Node ids and which tab is in front are not compared —
  /// switching tabs doesn't change a layout.
  static bool sameShape(LayoutNode? a, LayoutNode? b) => _shape(a) == _shape(b);

  static String _shape(LayoutNode? node) => switch (node) {
    null => '-',
    SplitNode(:final axis, :final children, :final sizes) =>
      '${axis.name}[${_shares(sizes)}]'
          '(${children.map(_shape).join(',')})',
    LeafNode(:final tabs) => '{${tabs.map((tab) => tab.id).join(',')}}',
  };

  /// Flex weights as shares of their total, to three places, so a tree that
  /// went through a projection compares equal to one laid out directly.
  static String _shares(List<PanelExtent> sizes) {
    final total = sizes.fold<double>(
      0,
      (sum, size) => size is FlexExtent ? sum + size.weight : sum,
    );
    return [
      for (final size in sizes)
        switch (size) {
          FlexExtent(:final weight) => (weight / total).toStringAsFixed(3),
          FixedExtent(:final pixels) => '${pixels.toStringAsFixed(0)}px',
        },
    ].join(',');
  }

  /// [tree] without every tab not in [keep], normalised; null when nothing
  /// is kept.
  static LayoutNode? project(LayoutNode tree, Set<String> keep) {
    LayoutNode? result = tree;
    for (final tab in tree.tabs) {
      if (!keep.contains(tab.id)) result = LayoutTree.removeTab(result, tab.id);
    }
    return result;
  }

  /// [root] with the area holding [tabId] resized to [share] of the room it
  /// and its neighbour have together — the sibling with [besideId], or,
  /// when that is gone (flattened into the parent split) or not given,
  /// every other child of the split. Fixed extents are left alone.
  static LayoutNode withShare(
    LayoutNode root,
    String tabId,
    double share, {
    String? besideId,
  }) {
    final leaf = root.leafOf(tabId);
    final parent = leaf == null ? null : root.parentOf(leaf.id);
    if (leaf == null || parent == null) return root;
    final index = parent.children.indexWhere((child) => child.id == leaf.id);
    final beside = besideId == null
        ? -1
        : parent.children.indexWhere((child) => child.id == besideId);
    final others = beside >= 0
        ? [beside]
        : [
            for (var i = 0; i < parent.children.length; i++)
              if (i != index) i,
          ];
    if ([index, ...others].any((i) => parent.sizes[i] is! FlexExtent)) {
      return root;
    }
    double weight(int i) => (parent.sizes[i] as FlexExtent).weight;
    final othersTotal = others.fold(0.0, (sum, i) => sum + weight(i));
    final total = othersTotal + weight(index);
    final clamped = share.clamp(0.1, 0.9);
    final sizes = List<PanelExtent>.of(parent.sizes);
    sizes[index] = PanelExtent.flex(total * clamped);
    for (final i in others) {
      sizes[i] = PanelExtent.flex(
        weight(i) / othersTotal * total * (1 - clamped),
      );
    }
    return LayoutTree.replace(root, parent.id, parent.copyWith(sizes: sizes))!;
  }

  /// The deepest node of [root] holding every tab in [tabIds].
  static LayoutNode _smallestHolding(LayoutNode root, Set<String> tabIds) {
    var node = root;
    while (node is SplitNode) {
      final next = node.children
          .where((child) => tabIds.every((id) => child.leafOf(id) != null))
          .firstOrNull;
      if (next == null) break;
      node = next;
    }
    return node;
  }

  static double _share(PanelExtent own, PanelExtent neighbour) {
    if (own is FlexExtent && neighbour is FlexExtent) {
      return own.weight / (own.weight + neighbour.weight);
    }
    return 0.5;
  }
}
