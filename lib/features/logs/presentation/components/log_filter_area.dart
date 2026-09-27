import 'package:flutter/material.dart';

import '../models/log_view_mode.dart';
import '../../log_controller.dart';
import 'classic_filter_bar.dart';
import 'filter_bar_shared.dart';
import 'inline_filter_bar.dart';
import 'log_search_field.dart';

/// The rows above the log list. The first puts **Search** (highlight and step
/// through matches) beside the filter controls (hide what doesn't match), so
/// neither is buried; the filter half is the pill bar's Filter / Level buttons
/// or the inline `key:value` field, cross-faded when the trailing toggle
/// switches modes. In pill mode the active filters get a row of their own.
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
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: inset),
                child: LogSearchField(controller: controller),
              ),
              const SizedBox(width: 8),
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
                      : Align(
                          key: const ValueKey('classic-filter-bar'),
                          alignment: Alignment.topLeft,
                          child: ClassicFilterBar(
                            controller: controller.classicFilter,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: EdgeInsets.only(top: inset),
                child: _ModeToggle(controller: controller, isInline: isInline),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topLeft,
            child: isInline || !controller.classicFilter.hasPills
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClassicFilterPills(
                      controller: controller.classicFilter,
                    ),
                  ),
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
      icon: Icon(isInline ? Icons.view_agenda_outlined : Icons.code, size: 17),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: kFilterControlHeight,
        height: kFilterControlHeight,
      ),
      padding: EdgeInsets.zero,
    );
  }
}
