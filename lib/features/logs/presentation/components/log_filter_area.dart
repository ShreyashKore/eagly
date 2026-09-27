import 'package:flutter/material.dart';

import '../models/log_view_mode.dart';
import '../../log_controller.dart';
import 'classic_filter_bar.dart';
import 'filter_bar_shared.dart';
import 'inline_filter_bar.dart';
import 'log_search_field.dart';

/// The row above the log list: the filter on the left (hide what doesn't
/// match), **Search** on the right (highlight and step through matches), and
/// the mode toggle at the end. The filter is the pill bar's type-to-filter
/// field — which holds the active pills — or the inline `key:value` field,
/// cross-faded when the toggle switches modes.
///
/// Narrower than [stackBelowWidth], the row stacks: the filter gets the full
/// width, with Level, Search and the toggle on a line below. Global keys carry
/// the filter and the search field across the switch, so typed text, focus
/// and an open menu survive a resize.
///
/// The search field stays outside the cross-fade: it shares
/// [LogController.searchFocusNode], which two fading copies can't both hold.
class LogFilterArea extends StatefulWidget {
  const LogFilterArea({super.key, required this.controller});

  final LogController controller;

  /// Below this width the filter and the Level / Search controls stack.
  static const double stackBelowWidth = 760;

  @override
  State<LogFilterArea> createState() => _LogFilterAreaState();
}

class _LogFilterAreaState extends State<LogFilterArea> {
  final GlobalKey _filterKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();

  LogController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final isInline = _controller.filterViewMode == LogFilterViewMode.inline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < LogFilterArea.stackBelowWidth
            ? _buildStacked(isInline: isInline)
            : _buildRow(isInline: isInline),
      ),
    );
  }

  Widget _buildRow({required bool isInline}) {
    // The inline field is taller than the row's controls; centre them on it.
    final inset = isInline
        ? (kFilterFieldHeight - kFilterControlHeight) / 2
        : 0.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildFilter(isInline: isInline, showLevel: true)),
        const SizedBox(width: 8),
        Padding(
          padding: EdgeInsets.only(top: inset),
          child: LogSearchField(key: _searchKey, controller: _controller),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: EdgeInsets.only(top: inset),
          child: _ModeToggle(controller: _controller, isInline: isInline),
        ),
      ],
    );
  }

  Widget _buildStacked({required bool isInline}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilter(isInline: isInline, showLevel: false),
        const SizedBox(height: 6),
        Row(
          children: [
            // The inline bar keeps its own level dropdown up with the field.
            if (!isInline) ...[
              ClassicLevelButton(controller: _controller.classicFilter),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: LogSearchField(
                key: _searchKey,
                controller: _controller,
                fillWidth: true,
              ),
            ),
            const SizedBox(width: 4),
            _ModeToggle(controller: _controller, isInline: isInline),
          ],
        ),
      ],
    );
  }

  Widget _buildFilter({required bool isInline, required bool showLevel}) {
    return AnimatedSwitcher(
      key: _filterKey,
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: isInline
          ? InlineFilterBar(
              key: const ValueKey('inline-filter-bar'),
              controller: _controller.inlineFilter,
            )
          : ClassicFilterBar(
              key: const ValueKey('classic-filter-bar'),
              controller: _controller.classicFilter,
              showLevel: showLevel,
            ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.controller, required this.isInline});

  final LogController controller;
  final bool isInline;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isInline
          ? 'Switch to filter pills'
          : 'Switch to typed filter (key:value syntax)',
      onPressed: () => controller.setFilterViewMode(
        isInline ? LogFilterViewMode.classic : LogFilterViewMode.inline,
      ),
      icon: Icon(isInline ? Icons.view_agenda_outlined : Icons.code, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: kFilterControlHeight,
        height: kFilterControlHeight,
      ),
      padding: EdgeInsets.zero,
    );
  }
}
