import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';
import 'log_lines_limit_input.dart';

/// Status-bar "Max lines" label that turns into an inline editor on tap.
class LogLinesLimitEditor extends StatelessWidget {
  const LogLinesLimitEditor({super.key, required this.controller});

  final LogController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: context.scaled(24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: controller.editingLogLinesLimit
          ? null
          : BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: !controller.editingLogLinesLimit
          ? InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => controller.setEditingLogLinesLimit(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Max lines: ${controller.logLinesLimit}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
          : IntrinsicWidth(
              child: LogLinesLimitInput(
                setEditingLogLinesLimit: controller.setEditingLogLinesLimit,
                submitLogLinesLimit: controller.submitLogLinesLimit,
                logLinesLimit: controller.logLinesLimit,
                isEditing: controller.editingLogLinesLimit,
              ),
            ),
    );
  }
}
