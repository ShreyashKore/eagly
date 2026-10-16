import 'package:flutter/material.dart';

import 'log_filter_controller.dart';
import 'log_filter_field.dart';
import 'log_level_button.dart';

export 'log_filter_controller.dart'
    show LogFilterController, LogFilterSuggestions;
export 'log_level_button.dart' show LogLevelButton;

/// The log filter bar: one type-to-filter field that holds the active
/// filters as pills, then a **Level** button.
///
/// Two ways in, one result:
/// * click the field and pick a field from its "Filter by…" menu — the new
///   pill opens its editor (field, operator, value);
/// * or just type: `tag:Auth`, `-message:noise`, `pid~:^12`, `level:e`,
///   `age:5m`. Space or ↵ turns each token into a pill, and plain text + ↵
///   adds the highlighted "Message contains …". Backspace in the empty field
///   marks the last pill, a second Backspace removes it.
///
/// Fully driven by a [LogFilterController]; it owns no filter state.
class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.controller,
    this.showLevel = true,
  });

  final LogFilterController controller;

  /// False when the host lays the [LogLevelButton] out elsewhere — the
  /// stacked narrow-window layout puts it beside search.
  final bool showLevel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: LogFilterField(controller: controller)),
          if (showLevel) ...[
            const SizedBox(width: 6),
            LogLevelButton(controller: controller),
          ],
        ],
      ),
    );
  }
}
