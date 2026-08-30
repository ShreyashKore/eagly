import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';

/// Bottom panel of the Utilities pane showing the latest run: a status pill,
/// the command line that ran, and its (selectable) output.
///
/// It is labelled "Result" and pinned to the bottom of the pane so it reads as
/// the answer to the tile that was just clicked, rather than as a second list.
class UtilityOutputPanel extends StatelessWidget {
  const UtilityOutputPanel({
    super.key,
    required this.result,
    required this.onClose,
    this.onRerun,
  });

  final UtilityRunResult result;
  final VoidCallback onClose;

  /// Runs the same command again. Null while another command is in flight or
  /// when the command is no longer available on this device.
  final VoidCallback? onRerun;

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
      constraints: const BoxConstraints(maxHeight: 300),
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
                _StatusPill(
                  color: statusColor,
                  icon: result.isSuccess
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  label: result.isSuccess
                      ? 'Result'
                      : 'Failed · exit ${result.exitCode}',
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    result.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onRerun != null)
                  IconButton(
                    tooltip: 'Run again',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onRerun,
                    icon: const Icon(Icons.refresh),
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
                  if (body.isEmpty)
                    Text(
                      'Finished with no output.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    SelectableText(
                      body,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const Gap(4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
