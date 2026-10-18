import 'package:flutter/material.dart';

class const GetStartedActionCard({
  super.key,
  required final IconData icon,
  required final String title,
  required final String subtitle,
  required final VoidCallback onTap,
  final List<Widget> secondaryActions = const [],
  final List<Widget> children = const [],
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            child: Column(
              spacing: 12,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary, size: 32),
                    // Expanded, or the subtitle is laid out at its full
                    // single-line width and paints overflow stripes: a Row
                    // gives an unflexed child infinite width, so the text
                    // never wraps no matter how narrow the card gets.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (secondaryActions.isNotEmpty)
                  // Wrap, not Row: a card narrowed by a small window has to
                  // fold its actions onto a second line rather than overflow.
                  Wrap(spacing: 8, runSpacing: 8, children: secondaryActions),
                if (children.isNotEmpty) Column(spacing: 8, children: children),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
