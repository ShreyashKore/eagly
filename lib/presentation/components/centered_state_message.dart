import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// A pane's empty, unsupported or failed state: an icon, a [title] and a
/// [description] centred in the pane, with an optional [footer] action.
class const CenteredStateMessage({
  super.key,
  required final IconData icon,
  required final String title,
  required final String description,
  final Widget? footer,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const Gap(16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (footer != null) ...[const Gap(20), footer!],
          ],
        ),
      ),
    );
  }
}

/// The "Try again" [CenteredStateMessage.footer] of a load that failed.
class const RetryButton({super.key, required final VoidCallback onPressed})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    );
  }
}
