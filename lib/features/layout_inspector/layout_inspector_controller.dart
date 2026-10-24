import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../data/device.dart';
import '../../features/app_log/app_logger.dart';
import '../../session/feature_controller.dart';
import '../../session/workspace_layout.dart';
import 'data/layout_parsers.dart';
import 'data/layout_snapshot.dart';
import 'data/view_hierarchy.dart';
import 'services/inspector_helper.dart';

/// A row of the inspector's tree: a window heading, or a node under it.
sealed class LayoutTreeRow {
  const LayoutTreeRow();
}

class const LayoutWindowRow(final LayoutWindow window) extends LayoutTreeRow;

class const LayoutNodeRow({
  required final LayoutNode node,

  /// Indent level, counted from the window's root.
  required final int depth,
}) extends LayoutTreeRow;

/// The Layout Inspector pane (docs/LAYOUT_INSPECTOR.md): captures what is on
/// an Android device's screen as a tree, with a screenshot to point at.
///
/// Captures go through Eagly's on-device helper when it can start (~0.2 s,
/// every window, and [live] updates), and through `uiautomator dump`
/// otherwise (~2 s, the active window). Either way the resumed activity's
/// View tree from `dumpsys` is joined in, for real class names.
///
/// The helper holds the device's only UI Automation connection, which a UI
/// test, Appium or Maestro would need, so it runs only while [live] is on
/// and for [helperLinger] after a capture, and never while the pane is
/// closed.
class LayoutInspectorController(super.session) extends FeatureController {
  /// How long the helper stays connected after a capture, so the next
  /// refresh skips its ~0.3 s start.
  @visibleForTesting
  static Duration helperLinger = const Duration(seconds: 20);

  final AppLogger _logger = AppLogger(source: 'LayoutInspector');

  LayoutSnapshot? _snapshot;
  String? _error;
  String? _notice;
  bool _capturing = false;
  bool _captureAgain = false;
  bool _live = false;
  bool _disposed = false;

  LayoutNode? _selected;
  LayoutNode? _hovered;
  final Set<String> _collapsed = {};
  final Set<String> _seenWindowRoots = {};
  String _query = '';
  bool _showAllBounds = false;

  InspectorHelper? _helper;
  Future<InspectorHelper?>? _helperStarting;
  StreamSubscription<void>? _changes;
  Timer? _lingerTimer;

  /// Set once the helper fails for a reason a retry won't fix (not `busy`):
  /// later captures go straight to `uiautomator`.
  bool _helperUnusable = false;

  LayoutSnapshot? get snapshot => _snapshot;

  /// Why the last capture failed; the previous snapshot stays shown.
  String? get error => _error;

  /// A note on how captures are being made, e.g. why live updates are off.
  String? get notice => _notice;
  bool get isCapturing => _capturing;

  /// Whether the tree follows the screen, recapturing as the UI changes.
  bool get live => _live;
  LayoutNode? get selected => _selected;
  LayoutNode? get hovered => _hovered;
  String get query => _query;

  /// Whether every node's bounds are outlined over the screenshot, not just
  /// the hovered and selected ones.
  bool get showAllBounds => _showAllBounds;

  /// Whether this device can be inspected at all: Android only, for now.
  bool get isSupported => device is AndroidDevice;

  /// Whether live updates can be offered: they need the helper.
  bool get canGoLive => isSupported && isConnected && !_helperUnusable;

  bool get _isPaneOpen => session.isPaneOpen(WorkspacePane.layoutInspector);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Capturing ─────────────────────────────────────────────────────────

  /// Captures once when the pane opens with nothing to show.
  Future<void> ensureCaptured() async {
    if (_snapshot != null || _capturing) return;
    await capture();
  }

  /// Captures the screen now. A capture asked for while one runs is folded
  /// into one more, run straight after.
  Future<void> capture() async {
    if (_disposed || !isSupported || !isConnected) return;
    if (_capturing) {
      _captureAgain = true;
      return;
    }
    _capturing = true;
    _notify();
    try {
      do {
        _captureAgain = false;
        await _captureOnce();
      } while (_captureAgain && !_disposed && isConnected);
    } finally {
      _capturing = false;
      _scheduleRelease();
      _notify();
    }
  }

  Future<void> _captureOnce() async {
    final views = service.dumpViewHierarchy().then<ViewHierarchy?>(
      (views) => views,
      onError: (Object error) {
        _logger.warning('dumpsys activity top failed', detail: '$error');
        return null;
      },
    );
    try {
      final LayoutSnapshot next;
      final helper = await _ensureHelper();
      if (helper != null) {
        final started = DateTime.now();
        final result = await helper.snapshot();
        next = parseHelperSnapshot(
          result,
          capturedAt: started,
          elapsed: DateTime.now().difference(started),
        );
      } else {
        next = await service.captureLayoutWithUiAutomator();
      }
      (await views)?.annotate(next);
      _apply(next);
      _error = null;
    } on InspectorHelperException catch (error) {
      _error = error.message;
    } catch (error) {
      _logger.warning('Layout capture failed', detail: '$error');
      _error = _describe(error);
    }
  }

  static String _describe(Object error) {
    final text = '$error';
    if (text.contains('could not get idle state')) {
      return 'The screen never stopped moving long enough for uiautomator to '
          'read it. Pause the animation, or capture again.';
    }
    return text.replaceFirst('FormatException: ', '');
  }

  void _apply(LayoutSnapshot next) {
    final previousSelected = _selected;
    _snapshot = next;
    for (final window in next.windows) {
      final root = window.root;
      if (root == null || !_seenWindowRoots.add(root.key)) continue;
      // System windows (status bar, navigation bar) start folded away.
      if (window.type != 'application') _collapsed.add(root.key);
    }
    _selected = previousSelected == null ? null : next.find(previousSelected);
    _hovered = null;
  }

  // ── The helper's lifetime ─────────────────────────────────────────────

  /// The running helper, started if need be; null when captures should use
  /// `uiautomator` instead. A `busy` failure is rethrown: `uiautomator`
  /// would be refused the same way.
  Future<InspectorHelper?> _ensureHelper() async {
    _lingerTimer?.cancel();
    final running = _helper;
    if (running != null && !running.isClosed) return running;
    if (_helperUnusable) return null;
    return _helperStarting ??= _startHelper().whenComplete(
      () => _helperStarting = null,
    );
  }

  Future<InspectorHelper?> _startHelper() async {
    try {
      final helper = await service.startInspectorHelper();
      if (_disposed || !_isPaneOpen || !isConnected) {
        unawaited(helper.close());
        return null;
      }
      _helper = helper;
      unawaited(helper.done.then((_) => _handleHelperExit(helper)));
      return helper;
    } on InspectorHelperException catch (error) {
      if (error.isBusy) rethrow;
      _useUiAutomator(error.message);
      return null;
    } catch (error) {
      _useUiAutomator('$error');
      return null;
    }
  }

  void _useUiAutomator(String reason) {
    _logger.warning('Inspector helper unavailable', detail: reason);
    _helperUnusable = true;
    _notice =
        'Using uiautomator: the inspector helper could not start '
        '($reason). Captures are slower and show the active window only.';
  }

  void _handleHelperExit(InspectorHelper helper) {
    if (_helper != helper) return;
    _helper = null;
    _changes?.cancel();
    _changes = null;
    if (_live) {
      _live = false;
      _notice = 'Live updates stopped: the inspector helper exited.';
      _notify();
    }
  }

  /// Lets the helper go after [helperLinger], unless live updates need it.
  void _scheduleRelease() {
    _lingerTimer?.cancel();
    if (_live || _helper == null) return;
    _lingerTimer = Timer(helperLinger, _releaseHelper);
  }

  void _releaseHelper() {
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _changes?.cancel();
    _changes = null;
    final helper = _helper;
    _helper = null;
    if (helper != null) unawaited(helper.close());
  }

  /// Turns live updates on or off. On, every change to the UI is followed
  /// by a capture, at most one at a time.
  Future<void> setLive(bool live) async {
    if (live == _live) return;
    if (!live) {
      _live = false;
      _changes?.cancel();
      _changes = null;
      unawaited(_helper?.watch(false).catchError((_) {}));
      _scheduleRelease();
      _notify();
      return;
    }
    if (!canGoLive) return;
    _live = true;
    _notify();
    try {
      final helper = await _ensureHelper();
      if (helper == null || !_live) {
        _live = false;
        _notify();
        return;
      }
      _changes ??= helper.changes.listen((_) => unawaited(capture()));
      await helper.watch(true);
      await capture();
    } on InspectorHelperException catch (error) {
      _live = false;
      _error = error.message;
      _notify();
    }
  }

  void toggleLive() => unawaited(setLive(!_live));

  @override
  void onSessionChanged() {
    if (!_isPaneOpen) _stopUsingDevice();
  }

  @override
  void onDeviceDisconnected() => _stopUsingDevice();

  @override
  void onDeviceConnected() {
    // A helper that failed for this connection may run on the next.
    _helperUnusable = false;
    _notice = null;
  }

  void _stopUsingDevice() {
    if (_helper == null && !_live) return;
    _live = false;
    _releaseHelper();
    _notify();
  }

  // ── Selection and the tree ────────────────────────────────────────────

  /// Selects [node] and unfolds the tree down to it.
  void select(LayoutNode? node) {
    if (node == _selected) return;
    _selected = node;
    if (node != null) {
      for (final ancestor in node.ancestorsAndSelf) {
        if (ancestor != node) _collapsed.remove(ancestor.key);
      }
    }
    _notify();
  }

  void hover(LayoutNode? node) {
    if (node == _hovered) return;
    _hovered = node;
    _notify();
  }

  /// The node under [point] on the screenshot, in device pixels.
  LayoutNode? nodeAt(Offset point) => _snapshot?.hitTest(point);

  bool isCollapsed(LayoutNode node) => _collapsed.contains(node.key);

  void toggleCollapsed(LayoutNode node) {
    if (!_collapsed.remove(node.key)) _collapsed.add(node.key);
    _notify();
  }

  /// Unfolds [node] and everything under it, or folds it all away.
  void setSubtreeCollapsed(LayoutNode node, bool collapsed) {
    for (final each in node.descendantsAndSelf) {
      if (each.children.isEmpty) continue;
      if (collapsed) {
        _collapsed.add(each.key);
      } else {
        _collapsed.remove(each.key);
      }
    }
    _notify();
  }

  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _notify();
  }

  void setShowAllBounds(bool show) {
    if (show == _showAllBounds) return;
    _showAllBounds = show;
    _notify();
  }

  /// Whether [node] matches the search: its class, the View's class, its
  /// id, text, content description or hint contain the query.
  bool matches(LayoutNode node) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return false;
    return [
      node.className,
      node.view?.className,
      node.resourceId,
      node.text,
      node.contentDescription,
      node.hint,
    ].any((value) => value != null && value.toLowerCase().contains(query));
  }

  /// The tree as rows. With a query, only matching nodes and the nodes
  /// above them are listed, folded or not.
  List<LayoutTreeRow> get treeRows {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    final searching = _query.trim().isNotEmpty;
    final rows = <LayoutTreeRow>[];
    for (final window in snapshot.windows) {
      final root = window.root;
      if (root == null) continue;
      if (searching) {
        final keep = <String>{};
        for (final node in root.descendantsAndSelf) {
          if (!matches(node)) continue;
          for (final ancestor in node.ancestorsAndSelf) {
            keep.add(ancestor.key);
          }
        }
        if (keep.isEmpty) continue;
        rows.add(LayoutWindowRow(window));
        _addRows(rows, root, 0, (node) => keep.contains(node.key), true);
      } else {
        rows.add(LayoutWindowRow(window));
        _addRows(rows, root, 0, (_) => true, false);
      }
    }
    return rows;
  }

  void _addRows(
    List<LayoutTreeRow> rows,
    LayoutNode node,
    int depth,
    bool Function(LayoutNode) include,
    bool ignoreCollapsed,
  ) {
    if (!include(node)) return;
    rows.add(LayoutNodeRow(node: node, depth: depth));
    if (!ignoreCollapsed && isCollapsed(node)) return;
    for (final child in node.children) {
      _addRows(rows, child, depth + 1, include, ignoreCollapsed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _releaseHelper();
    super.dispose();
  }
}
