import 'dart:async';

import 'package:flutter/material.dart';

import 'animation_utils.dart';

/// Reveals [child] only after [delay] has elapsed while [enabled] stays true.
///
/// The "still stuck?" affordance: extra explanation stays out of the way for
/// users who do not need it, and appears on its own for users who have clearly
/// been waiting on something. The timer restarts whenever [enabled] flips back
/// on or [restartKey] changes, so a retried operation gets a fresh grace
/// period. The child is not built at all until the reveal fires — it is not
/// merely collapsed, so it stays out of the semantics tree and out of
/// `find.byType`/`find.text` in widget tests. (`AnimatedSection` alone would
/// keep it mounted at `heightFactor: 0`, which reads as "visible" to a test.)
class const DelayedReveal({
  super.key,
  required this.child,
  this.delay = const Duration(seconds: 8),
  this.enabled = true,
  this.restartKey,
}) extends StatefulWidget {
  final Widget child;

  /// How long [enabled] must stay true before [child] appears.
  final Duration delay;

  /// While false the child is hidden and the timer is held back.
  final bool enabled;

  /// Changing this value hides the child and restarts the delay.
  final Object? restartKey;

  @override
  State<DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<DelayedReveal> {
  Timer? _timer;
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(DelayedReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.delay != oldWidget.delay ||
        widget.restartKey != oldWidget.restartKey) {
      _restart();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _revealed = false;
    if (!widget.enabled) return;
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _revealed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContent(
      child: _revealed ? widget.child : const SizedBox.shrink(),
    );
  }
}
