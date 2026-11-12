import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../presentation/components/feature_view.dart';
import '../../../../presentation/components/min_width_box.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';
import 'log_filter_bar.dart';
import 'log_framework_chips.dart';
import 'log_search_field.dart';

/// The row above the log list: the filter on the left (hide what doesn't
/// match) and **Search** on the right (highlight and step through matches).
/// The filter is the pill bar's type-to-filter field, which holds the active
/// pills. The framework chips ([LogFrameworkChips]) sit right beside the
/// filter, drawn only once the logs show a framework's lines.
///
/// Narrower than [stackBelowWidth], the row stacks: the filter and the chips
/// share the first line, with Level and Search on a line below. Global keys
/// carry the filter, the chips and the search field across the switch, so
/// typed text, focus and an open menu survive a resize. A pane narrower than
/// [minWidth] clips the row's right edge rather than squeezing its controls.
class const LogFilterArea({super.key, required final LogController controller})
    extends StatefulWidget {
  /// Below this width (at 1× zoom; it scales with the zoom) the filter and
  /// the Level / Search controls stack.
  static const double stackBelowWidth = 1050;

  /// The narrowest (at 1× zoom) the stacked controls lay out without
  /// overflowing.
  static const double minWidth = 320;

  /// Below this width (at 1× zoom) the stacked layout's framework chips show
  /// only their logos, leaving the filter field room.
  static const double compactChipsBelowWidth = 560;

  @override
  State<LogFilterArea> createState() => _LogFilterAreaState();
}

class _LogFilterAreaState extends State<LogFilterArea> {
  final GlobalKey _filterKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _frameworksKey = GlobalKey();
  final ScrollController _chipsScroll = ScrollController();

  LogController get _controller => widget.controller;

  @override
  void dispose() {
    _chipsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FeatureSubBar(
      child: MinWidthBox(
        minWidth: context.scaled(LogFilterArea.minWidth),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth <
                  context.scaled(LogFilterArea.stackBelowWidth)
              ? _buildStacked()
              : _buildRow(),
        ),
      ),
    );
  }

  Widget _buildRow() {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildFilter(showLevel: true)),
          // Capped as in the stacked layout, so many detected frameworks
          // scroll instead of pushing Search off the row.
          _buildFrameworks(
            compact: false,
            leadingGap: 8,
            maxWidth: constraints.maxWidth / 3,
          ),
          const SizedBox(width: 8),
          LogSearchField(key: _searchKey, controller: _controller),
        ],
      ),
    );
  }

  Widget _buildStacked() {
    return LayoutBuilder(
      builder: (context, constraints) => _buildStackedColumn(
        compactChips:
            constraints.maxWidth <
            context.scaled(LogFilterArea.compactChipsBelowWidth),
      ),
    );
  }

  Widget _buildStackedColumn({required bool compactChips}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFilter(showLevel: false)),
              // Capped so the filter field keeps room; past it the chips
              // scroll sideways.
              _buildFrameworks(
                compact: compactChips,
                leadingGap: 6,
                maxWidth: constraints.maxWidth / 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            LogLevelButton(controller: _controller.filter),
            const SizedBox(width: 6),
            Expanded(
              child: LogSearchField(
                key: _searchKey,
                controller: _controller,
                fillWidth: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The framework chips, with [leadingGap] before them only while there are
  /// any to show. Wider than [maxWidth], they scroll sideways: by trackpad,
  /// by mouse drag, or by a plain vertical mouse wheel.
  Widget _buildFrameworks({
    required bool compact,
    required double leadingGap,
    required double maxWidth,
  }) {
    final filter = _controller.filter;
    return ListenableBuilder(
      key: _frameworksKey,
      listenable: filter,
      builder: (context, _) {
        if (filter.visibleFrameworks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(left: leadingGap),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Listener(
              onPointerSignal: _scrollChipsByWheel,
              child: ScrollConfiguration(
                // A desktop mouse can't drag a scrollable by default; let it,
                // as the pane headers do. A scrollbar would cover the chips.
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: PointerDeviceKind.values.toSet(),
                ),
                child: SingleChildScrollView(
                  controller: _chipsScroll,
                  scrollDirection: Axis.horizontal,
                  child: LogFrameworkChips(
                    controller: filter,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Turns a vertical wheel tick over the chips into a sideways scroll. The
  /// horizontal scrollable claims only horizontal (or Shift+wheel) deltas, so
  /// a plain mouse wheel would otherwise do nothing there.
  void _scrollChipsByWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta.dy == 0 || delta.dx != 0) return;
    if (!_chipsScroll.hasClients) return;
    if (_chipsScroll.position.maxScrollExtent <= 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!_chipsScroll.hasClients) return;
      final position = _chipsScroll.position;
      position.jumpTo(
        (position.pixels + delta.dy).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  Widget _buildFilter({required bool showLevel}) => LogFilterBar(
    key: _filterKey,
    controller: _controller.filter,
    showLevel: showLevel,
  );
}
