import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';

/// Bottom panel of the Utilities pane showing the latest run: the command line
/// that ran, its status, and its (selectable) output.
class UtilityOutputPanel extends StatelessWidget {
  const UtilityOutputPanel({
    super.key,
    required this.result,
    required this.onClose,
  });

  final UtilityRunResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    final failure = result.failure;
    final body = failure ?? result.output.trim();

    final statusColor = result.isSuccess
        ? eaglyTheme.statusLiveColor
        : theme.colorScheme.error;

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  result.isSuccess
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 16,
                  color: statusColor,
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    result.isSuccess
                        ? result.label
                        : '${result.label} · exit ${result.exitCode}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy output',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: result.copyText),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: 'Dismiss output',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '\$ ${result.commandLine}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Gap(8),
                  SelectableText(
                    body.isEmpty ? '(no output)' : body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: failure != null ? theme.colorScheme.error : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
