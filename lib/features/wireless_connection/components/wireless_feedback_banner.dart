import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Inline banner showing the latest wireless pairing/connection feedback.
///
/// Renders nothing when both [message] and [error] are absent; [error] takes
/// precedence and switches the banner to the error color scheme. An explained
/// error adds [detail] under the headline, the raw tool output as [rawOutput]
/// in small print, and any [actions] the user can take.
class const WirelessFeedbackBanner({
  super.key,
  final String? message,
  final String? error,
  final String? detail,
  final String? rawOutput,
  final List<Widget> actions = const [],
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = error ?? message;
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    final isError = error != null;
    final background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;
    final hasDetail = detail != null && detail!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: foreground,
            size: 18,
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: hasDetail ? FontWeight.w600 : null,
                  ),
                ),
                if (hasDetail) ...[
                  const Gap(4),
                  Text(
                    detail!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
                if (rawOutput != null && rawOutput!.isNotEmpty) ...[
                  const Gap(6),
                  SelectableText(
                    'adb: ${rawOutput!.trim()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.7),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const Gap(10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
