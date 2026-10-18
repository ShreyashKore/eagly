import 'package:flutter/material.dart';

/// Reports its row's [BuildContext] to the parent [LogViewer] on mount,
/// index change, and unmount so the viewer can measure row bounds for
/// drag-selection hit-testing.
class const RowBoundsReporter({
  required final int index,
  required final void Function(int index, BuildContext context) onMounted,
  required final void Function(int index, BuildContext context) onUnmounted,
  required final Widget child,
  required super.key,
}) extends StatefulWidget {
  @override
  State<RowBoundsReporter> createState() => _RowBoundsReporterState();
}

class _RowBoundsReporterState extends State<RowBoundsReporter> {
  @override
  void initState() {
    super.initState();
    _reportMounted();
  }

  @override
  void didUpdateWidget(covariant RowBoundsReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      widget.onUnmounted(oldWidget.index, context);
    }
    _reportMounted();
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.index, context);
    super.dispose();
  }

  void _reportMounted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMounted(widget.index, context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
