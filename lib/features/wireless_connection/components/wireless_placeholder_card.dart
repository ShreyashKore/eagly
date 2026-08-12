import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Empty-state card shown when a wireless tab has nothing to display yet.
class WirelessPlaceholderCard extends StatelessWidget {
  const WirelessPlaceholderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Optional actions shown below the description.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const Gap(12),
          Text(title, style: theme.textTheme.titleMedium),
          const Gap(8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (footer != null) ...[const Gap(16), footer!],
        ],
      ),
    );
  }
}
