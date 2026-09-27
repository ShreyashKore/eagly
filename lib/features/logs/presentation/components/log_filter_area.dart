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
/// The search field stays outside the cross-fade: it shares
/// [LogController.searchFocusNode], which two fading copies can't both hold.
class LogFilterArea extends StatelessWidget {
  const LogFilterArea({super.key, required this.controller});

  final LogController controller;

  @override
  Widget build(BuildContext context) {
    final isInline = controller.filterViewMode == LogFilterViewMode.inline;
    // The inline field is taller than the row's controls; centre them on it.
    final inset = isInline
        ? (kFilterFieldHeight - kFilterControlHeight) / 2
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedSwitcher(
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
                      controller: controller.inlineFilter,
                    )
                  : ClassicFilterBar(
                      key: const ValueKey('classic-filter-bar'),
                      controller: controller.classicFilter,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: EdgeInsets.only(top: inset),
            child: LogSearchField(controller: controller),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: EdgeInsets.only(top: inset),
            child: _ModeToggle(controller: controller, isInline: isInline),
          ),
        ],
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
