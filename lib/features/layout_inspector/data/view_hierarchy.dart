import 'dart:ui';

import 'layout_snapshot.dart';

/// One `View` from `dumpsys activity top`: its real class (where the
/// accessibility tree only has the nearest framework class), its resource
/// name and its flags. See docs/LAYOUT_INSPECTOR.md §2.2.
class ViewNode({
  required final String className,

  /// Device pixels, accumulated from the parent-relative bounds `View`
  /// prints. Scroll offsets and translations aren't printed, so inside a
  /// scrolled container these drift from what is on screen.
  required final Rect bounds,

  /// The id as `View.toString` prints it: `app:id/submit` for the app's own
  /// resources, `android:id/content` for the framework's.
  final String? resourceName,

  /// The raw id in hex, when the view has one (`7f0a01e5`).
  final String? idHex,

  /// `View.toString`'s two flag blocks, e.g. `VFED..C..` and `........`.
  final String viewFlags = '',
  final String stateFlags = '',
  final List<ViewNode> children = const [],
}) {
  String get shortClassName {
    final dot = className.lastIndexOf('.');
    return dot < 0 ? className : className.substring(dot + 1);
  }

  String? get resourceEntry {
    final name = resourceName;
    if (name == null) return null;
    final slash = name.indexOf(':id/');
    return slash < 0 ? null : name.substring(slash + 4);
  }

  /// `visible`, `invisible` or `gone`.
  String get visibility => switch (_flag(viewFlags, 0)) {
    'I' => 'invisible',
    'G' => 'gone',
    _ => 'visible',
  };

  /// The flags worth showing, by name: `focusable`, `clickable`, `pressed`, …
  List<String> get flagNames => [
    if (_flag(viewFlags, 1) == 'F') 'focusable',
    if (_flag(viewFlags, 2) != 'E') 'disabled',
    if (_flag(viewFlags, 3) == '.') 'willNotDraw',
    if (_flag(viewFlags, 6) == 'C') 'clickable',
    if (_flag(viewFlags, 7) == 'L') 'longClickable',
    if (_flag(viewFlags, 8) == 'X') 'contextClickable',
    if (_flag(stateFlags, 1) == 'F') 'focused',
    if (_flag(stateFlags, 2) == 'S') 'selected',
    if (_flag(stateFlags, 3) == 'P' || _flag(stateFlags, 3) == 'p') 'pressed',
    if (_flag(stateFlags, 4) == 'H') 'hovered',
    if (_flag(stateFlags, 5) == 'A') 'activated',
  ];

  Iterable<ViewNode> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }

  static String _flag(String flags, int index) =>
      index < flags.length ? flags[index] : '.';
}

/// The resumed activity's View tree, read from `dumpsys activity top`. It
/// works in any app, debuggable or not, in ~0.1 s; what it lacks is text,
/// which the accessibility tree has, so [annotate] joins the two.
class ViewHierarchy({
  /// `com.example/.MainActivity`.
  required final String activity,
  required final List<ViewNode> roots,
}) {
  /// The package the activity belongs to.
  String get packageName => activity.split('/').first;

  /// Parses `dumpsys activity top`, which dumps the top activity of every
  /// visible task — the launcher behind a translucent app, say. The resumed
  /// one is picked, or failing that the last one with a View tree. Null when
  /// no activity printed one.
  static ViewHierarchy? parse(String dumpsys) {
    final sections = <_Section>[];
    _Section? current;
    for (final raw in dumpsys.split('\n')) {
      final line = raw.trimRight();
      final activity = _activityLine.firstMatch(line);
      if (activity != null) {
        sections.add(current = _Section(activity.group(1)!));
        continue;
      }
      if (current == null) continue;
      if (line.contains('mResumed=true')) current.resumed = true;
      if (line == '    View Hierarchy:') {
        current.collecting = true;
      } else if (current.collecting) {
        // The tree is indented past its heading; the next heading ends it.
        if (line.isNotEmpty && !line.startsWith('      ')) {
          current.collecting = false;
        } else {
          current.add(line);
        }
      }
    }
    final withViews = sections.where((section) => section.roots.isNotEmpty);
    final best =
        withViews.where((section) => section.resumed).lastOrNull ??
        withViews.lastOrNull;
    if (best == null) return null;
    return ViewHierarchy(
      activity: best.activity,
      roots: [for (final root in best.roots) root.build(Offset.zero)],
    );
  }

  /// Pairs every accessibility node of this activity's app with the View it
  /// came from, setting [LayoutNode.view].
  ///
  /// There is no shared id to join on (the `aid=` `View` prints is its
  /// autofill id, not its accessibility id), so nodes are paired by equal
  /// bounds, in depth-first order, each View used once. A pair whose
  /// resource ids both exist and differ is refused. That is exact for
  /// leaves and a fair guess for full-screen containers nested in each
  /// other, which line up in the same order in both trees.
  void annotate(LayoutSnapshot snapshot) {
    final views = [
      for (final root in roots)
        for (final view in root.descendantsAndSelf)
          if (view.visibility != 'gone') view,
    ];
    final used = List.filled(views.length, false);
    var start = 0;
    for (final node in snapshot.nodes) {
      if (node.packageName != packageName) continue;
      final entry = node.resourceEntry;
      for (var i = start; i < views.length; i++) {
        if (used[i] || views[i].bounds != node.bounds) continue;
        final viewEntry = views[i].resourceEntry;
        if (entry != null && viewEntry != null && entry != viewEntry) continue;
        used[i] = true;
        node.view = views[i];
        // Later nodes come later in the View tree too; skip what's behind.
        while (start < views.length && used[start]) {
          start++;
        }
        break;
      }
    }
  }

  static final _activityLine = RegExp(r'^  ACTIVITY (\S+) ');
}

/// One activity's lines while they are read.
class _Section(final String activity) {
  bool resumed = false;
  bool collecting = false;
  final List<_PendingView> roots = [];
  final List<(int, _PendingView)> _stack = [];

  void add(String line) {
    final indent = line.length - line.trimLeft().length;
    final view = _PendingView.parse(line.trimLeft());
    if (view == null) return;
    while (_stack.isNotEmpty && _stack.last.$1 >= indent) {
      _stack.removeLast();
    }
    if (_stack.isEmpty) {
      roots.add(view);
    } else {
      _stack.last.$2.children.add(view);
    }
    _stack.add((indent, view));
  }
}

/// A View line before its parent's position is known.
class _PendingView({
  required final String className,
  final Rect? local,
  final String? resourceName,
  final String? idHex,
  final String viewFlags = '',
  final String stateFlags = '',
}) {
  final List<_PendingView> children = [];

  /// A line like
  /// `android.widget.FrameLayout{76e6 V.E...... ........ 0,0-1080,2280 #1020002 android:id/content aid=1073741826}`,
  /// or the root's `DecorView@4273ad2[MainActivity]`. Anything else (a
  /// drawable holder some libraries print) is null.
  static _PendingView? parse(String line) {
    final view = _viewLine.firstMatch(line);
    if (view != null) {
      return _PendingView(
        className: view.group(1)!,
        viewFlags: view.group(2)!,
        stateFlags: view.group(3)!,
        local: Rect.fromLTRB(
          double.parse(view.group(4)!),
          double.parse(view.group(5)!),
          double.parse(view.group(6)!),
          double.parse(view.group(7)!),
        ),
        idHex: view.group(8),
        resourceName: view.group(9),
      );
    }
    if (_decorLine.hasMatch(line)) {
      return _PendingView(className: 'com.android.internal.policy.DecorView');
    }
    return null;
  }

  /// [origin] is the parent's top-left on screen. The root DecorView prints
  /// no bounds; it is taken to sit at the origin and span its children.
  ViewNode build(Offset origin) {
    final local = this.local;
    final topLeft = local == null ? origin : origin + local.topLeft;
    final built = [for (final child in children) child.build(topLeft)];
    final Rect bounds;
    if (local != null) {
      bounds = local.shift(origin);
    } else if (built.isEmpty) {
      bounds = Rect.fromLTWH(origin.dx, origin.dy, 0, 0);
    } else {
      bounds = built
          .map((child) => child.bounds)
          .reduce((a, b) => a.expandToInclude(b));
    }
    return ViewNode(
      className: className,
      bounds: bounds,
      resourceName: resourceName,
      idHex: idHex,
      viewFlags: viewFlags,
      stateFlags: stateFlags,
      children: built,
    );
  }

  static final _viewLine = RegExp(
    r'^([\w.$]+)\{[0-9a-f]+ ([VIG.][F.][E.][D.][H.][V.][C.][L.][X.]?) '
    r'([R.][F.][S.][pP.][H.][A.][I.][D.]) '
    r'(-?\d+),(-?\d+)-(-?\d+),(-?\d+)'
    r'(?: #([0-9a-f]+)(?: ([^\s}]+:id/[^\s}]+))?)?',
  );
  static final _decorLine = RegExp(r'^DecorView@[0-9a-f]+\[');
}
