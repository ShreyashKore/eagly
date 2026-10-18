import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';

/// Bottom panel of the Utilities pane showing the latest run: a status pill,
/// the command line that ran, and its (selectable) output.
///
/// It is labelled "Result" and pinned to the bottom of the pane so it reads as
/// the answer to the tile that was just clicked, rather than as a second list.
class const UtilityOutputPanel({
  super.key,
  required final UtilityRunResult result,
  required final VoidCallback onClose,

  /// Runs the same command again. Null while another command is in flight or
  /// when the command is no longer available on this device.
  final VoidCallback? onRerun,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                UtilityStatusPill(result: result),
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
                  AppIconButton(
                    tooltip: 'Run again',
                    iconSize: 16,
                    onPressed: onRerun,
                    icon: Icons.refresh,
                  ),
                AppIconButton(
                  tooltip: 'Copy output',
                  iconSize: 16,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: result.copyText),
                    );
                  },
                  icon: Icons.copy_all_outlined,
                ),
                AppIconButton(
                  tooltip: 'Dismiss output',
                  iconSize: 16,
                  onPressed: onClose,
                  icon: Icons.close,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: UtilityOutputBody(result: result),
            ),
          ),
        ],
      ),
    );
  }
}

/// The command line that ran and its selectable output (or failure), shared
/// by this panel and the result dialog a run from outside the pane opens.
class const UtilityOutputBody({
  super.key,
  required final UtilityRunResult result,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    final failure = result.failure;
    final body = failure ?? result.output.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          '\$ ${result.commandLine}',
          style: eaglyTheme.monoStyle.copyWith(
            fontSize: 11,
            height: 1.35,
            color: eaglyTheme.tertiaryTextColor,
          ),
        ),
        const Gap(8),
        if (body.isEmpty)
          Text(
            'Finished with no output.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: eaglyTheme.tertiaryTextColor,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          SelectableText(
            body,
            style: eaglyTheme.monoStyle.copyWith(
              fontSize: 12,
              height: 1.35,
              color: failure != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            ),
          ),
      ],
    );
  }
}

/// "Result" or "Failed · exit N", coloured by outcome.
class const UtilityStatusPill({
  super.key,
  required final UtilityRunResult result,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = result.isSuccess
        ? context.eaglyTheme.statusLiveColor
        : theme.colorScheme.error;
    final icon = result.isSuccess
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final label = result.isSuccess
        ? 'Result'
        : 'Failed · exit ${result.exitCode}';

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
