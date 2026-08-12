import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Inline banner showing the latest wireless pairing/connection feedback.
///
/// Renders nothing when both [message] and [error] are absent; [error] takes
/// precedence and switches the banner to the error color scheme.
class WirelessFeedbackBanner extends StatelessWidget {
  const WirelessFeedbackBanner({super.key, this.message, this.error});

  final String? message;
  final String? error;

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
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
