import 'package:flutter/widgets.dart';

/// Which rows of a lazily built list are built right now, by a stable id.
///
/// For a list under a `SelectionArea` whose rows can be removed under it —
/// a live log, a terminal scrollback. Flutter's selection delegates remember
/// the last selection edges (a click leaves a collapsed selection, so nearly
/// always) and which rows hold them. When such a row is disposed, or the list
/// empties and its container leaves the area, they replay those edges against
/// whatever is there next and throw from a post-frame callback
/// (flutter/flutter#196102; Sentry FLUTTER-E, and FLUTTER-3T once a flush has
/// been cut short). So before a rebuild that drops built rows the list clears
/// the selection — from `didUpdateWidget`, while the delegates still agree
/// with the tree — and this registry is how it tells.
///
/// Rows register through [BuiltRowMarker] when they mount and leave when they
/// are disposed; between frames it holds every built row, including the ones
/// kept alive offscreen because they hold part of the selection.
class BuiltRowRegistry {
  final Map<int, int> _counts = <int, int>{};

  /// Whether some built row's id fails [isStillListed]: the next rebuild
  /// disposes a row the selection may be anchored in.
  bool anyRemoved(bool Function(int id) isStillListed) {
    for (final id in _counts.keys) {
      if (!isStillListed(id)) return true;
    }
    return false;
  }

  void _add(int id) => _counts.update(id, (n) => n + 1, ifAbsent: () => 1);

  void _remove(int id) {
    final n = _counts[id];
    if (n == null) return;
    if (n <= 1) {
      _counts.remove(id);
    } else {
      _counts[id] = n - 1;
    }
  }
}

/// Records its row in a [BuiltRowRegistry] for as long as it is mounted.
class const BuiltRowMarker({
  super.key,
  required final int id,
  required final BuiltRowRegistry registry,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<BuiltRowMarker> createState() => _BuiltRowMarkerState();
}

class _BuiltRowMarkerState extends State<BuiltRowMarker> {
  @override
  void initState() {
    super.initState();
    widget.registry._add(widget.id);
  }

  @override
  void didUpdateWidget(BuiltRowMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.registry != widget.registry) {
      oldWidget.registry._remove(oldWidget.id);
      widget.registry._add(widget.id);
    }
  }

  @override
  void dispose() {
    widget.registry._remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
