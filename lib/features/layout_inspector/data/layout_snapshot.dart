import 'dart:typed_data';
import 'dart:ui';

import 'view_hierarchy.dart';

/// Where a [LayoutSnapshot] came from (docs/LAYOUT_INSPECTOR.md §2).
enum LayoutSource {
  /// Eagly's on-device helper: every window, fast enough to follow the UI.
  helper('Inspector helper'),

  /// `uiautomator dump` and `screencap`: the active window only, ~2 s.
  uiautomator('uiautomator dump');

  const LayoutSource(this.label);

  final String label;
}

/// One node of the accessibility tree: what UI Automation, Appium and
/// Maestro see of a view, a Compose semantics node or a React Native view.
///
/// [bounds] are in device pixels, in the display's current rotation, like
/// the screenshot they are drawn over.
class LayoutNode({
  /// Where the node sits: window index, then child indexes (`0.2.1`). Stable
  /// while the UI keeps its shape, so selection survives a refresh.
  required final String key,
  required final String className,
  final String? packageName,
  final String? resourceId,
  final String? text,
  final String? contentDescription,
  final String? hint,
  final String? stateDescription,
  final String? paneTitle,
  required final Rect bounds,
  final Set<String> flags = const {},
  final List<LayoutNode> children = const [],
}) {
  /// The node above this one; null for a window's root.
  LayoutNode? get parent => _parent;
  LayoutNode? _parent;

  /// The `View` behind this node, matched from `dumpsys activity top`
  /// (see [ViewHierarchy.annotate]); null when no view lined up with it.
  ViewNode? view;

  int get depth => key.split('.').length - 1;

  /// The class without its package: `TextView` for `android.widget.TextView`.
  String get shortClassName => _shortName(className);

  /// The resource id's entry name: `submit` for `com.example:id/submit`. An
  /// id without a type (a React Native `testID`) is returned whole.
  String? get resourceEntry {
    final id = resourceId;
    if (id == null) return null;
    final slash = id.indexOf(':id/');
    return slash < 0 ? id : id.substring(slash + 4);
  }

  bool hasFlag(String flag) => flags.contains(flag);
  bool get isVisible => flags.isEmpty || hasFlag('visible');

  /// A one-line description for trees and menus: the short class, then the
  /// id, then the text or content description.
  String get label {
    final parts = <String>[view?.shortClassName ?? shortClassName];
    final entry = resourceEntry;
    if (entry != null) parts.add('#$entry');
    final words = text ?? contentDescription;
    if (words != null) parts.add('"${_singleLine(words)}"');
    return parts.join(' ');
  }

  /// This node and everything under it, depth first.
  Iterable<LayoutNode> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }

  /// From the window's root down to this node.
  List<LayoutNode> get ancestorsAndSelf {
    final chain = <LayoutNode>[];
    for (LayoutNode? node = this; node != null; node = node.parent) {
      chain.add(node);
    }
    return chain.reversed.toList();
  }

  void _link() {
    for (final child in children) {
      child._parent = this;
      child._link();
    }
  }

  @override
  String toString() => 'LayoutNode($key $label $bounds)';
}

/// A window on the display: an app, a dialog, the keyboard, the status bar.
class LayoutWindow({
  required final int id,
  required final String type,
  final String? title,
  final int layer = 0,
  final bool active = false,
  final bool focused = false,
  required final Rect bounds,
  final LayoutNode? root,
}) {
  /// "Home (application)", or just the type when the window has no title.
  String get label => title == null || title!.isEmpty ? type : '$title ($type)';
}

/// The UI at one moment: its windows, the display they are on, and a
/// screenshot taken alongside, so boxes drawn over it line up.
class LayoutSnapshot({
  /// Top-most first, the order a tap reaches them in.
  required final List<LayoutWindow> windows,

  /// The display in its current rotation, in device pixels.
  required final Size displaySize,

  /// Surface.ROTATION_*: 0–3, quarter turns clockwise.
  final int rotation = 0,

  /// Display density in dpi, when known: 160 is 1 px per dp.
  final int? densityDpi,

  /// The screenshot's encoded bytes (PNG or JPEG), when one was taken.
  final Uint8List? screenshot,
  required final DateTime capturedAt,
  required final LayoutSource source,

  /// How long the capture took, end to end.
  final Duration elapsed = Duration.zero,
}) {
  this {
    for (final window in windows) {
      window.root?._link();
    }
  }

  /// Every node of every window, top-most window first.
  Iterable<LayoutNode> get nodes sync* {
    for (final window in windows) {
      final root = window.root;
      if (root != null) yield* root.descendantsAndSelf;
    }
  }

  int get nodeCount => nodes.length;

  LayoutNode? nodeByKey(String key) {
    for (final node in nodes) {
      if (node.key == key) return node;
    }
    return null;
  }

  /// The window a node belongs to.
  LayoutWindow? windowOf(LayoutNode node) {
    final index = int.tryParse(node.key.split('.').first);
    if (index == null || index < 0 || index >= windows.length) return null;
    return windows[index];
  }

  /// The node a tap at [point] (device pixels) would land on: in the
  /// top-most window with a node under the point, the smallest visible node
  /// containing it. Smallest rather than deepest, because a container's
  /// later child can cover an earlier one's whole area.
  LayoutNode? hitTest(Offset point) {
    for (final window in windows) {
      final root = window.root;
      if (root == null || !root.bounds.contains(point)) continue;
      LayoutNode? best;
      var bestArea = double.infinity;
      for (final node in root.descendantsAndSelf) {
        if (!node.isVisible || !node.bounds.contains(point)) continue;
        final area = node.bounds.width * node.bounds.height;
        // `<=`: on a tie the later node in depth-first order is the deeper
        // or later-drawn one.
        if (area <= bestArea) {
          best = node;
          bestArea = area;
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// [previous]'s counterpart in this snapshot, so a selection survives a
  /// refresh: the node at the same key with the same class, or failing that
  /// the one with the same id and bounds.
  LayoutNode? find(LayoutNode previous) {
    final sameKey = nodeByKey(previous.key);
    if (sameKey != null && sameKey.className == previous.className) {
      return sameKey;
    }
    for (final node in nodes) {
      if (node.className == previous.className &&
          node.resourceId == previous.resourceId &&
          node.bounds == previous.bounds) {
        return node;
      }
    }
    return null;
  }
}

String _shortName(String className) {
  final dot = className.lastIndexOf('.');
  return dot < 0 ? className : className.substring(dot + 1);
}

String _singleLine(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > 40 ? '${line.substring(0, 39)}…' : line;
}
