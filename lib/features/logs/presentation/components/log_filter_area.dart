import 'package:flutter/material.dart';

import '../../../../presentation/components/min_width_box.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';
import 'log_filter_bar.dart';
import 'log_search_field.dart';

/// The row above the log list: the filter on the left (hide what doesn't
/// match) and **Search** on the right (highlight and step through matches).
/// The filter is the pill bar's type-to-filter field, which holds the active
/// pills.
///
/// Narrower than [stackBelowWidth], the row stacks: the filter gets the full
/// width, with Level and Search on a line below. Global keys carry the filter
/// and the search field across the switch, so typed text, focus and an open
/// menu survive a resize. A pane narrower than [minWidth] clips the row's
/// right edge rather than squeezing its controls.
class const LogFilterArea({super.key, required this.controller})
    extends StatefulWidget {
  final LogController controller;

  /// Below this width (at 1× zoom; it scales with the zoom) the filter and
  /// the Level / Search controls stack.
  static const double stackBelowWidth = 1050;

  /// The narrowest (at 1× zoom) the stacked controls lay out without
  /// overflowing.
  static const double minWidth = 320;

  @override
  State<LogFilterArea> createState() => _LogFilterAreaState();
}

class _LogFilterAreaState extends State<LogFilterArea> {
  final GlobalKey _filterKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();

  LogController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildFilter(showLevel: true)),
        const SizedBox(width: 8),
        LogSearchField(key: _searchKey, controller: _controller),
      ],
    );
  }

  Widget _buildStacked() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilter(showLevel: false),
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

  Widget _buildFilter({required bool showLevel}) => LogFilterBar(
    key: _filterKey,
    controller: _controller.filter,
    showLevel: showLevel,
  );
}
