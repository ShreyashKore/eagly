import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'discovered_wireless_target.dart';

/// Selectable card summarizing one discovered wireless ADB device.
class WirelessDiscoveryCard extends StatelessWidget {
  const WirelessDiscoveryCard({
    super.key,
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final DiscoveredWirelessTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 320,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        target.host,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                ),
                const Gap(8),
                Text(
                  target.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (target.pairingAddress != null)
                      Chip(
                        avatar: const Icon(Icons.password, size: 16),
                        label: Text(target.pairingAddress!),
                      ),
                    if (target.canConnect)
                      Chip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: Text(target.connectSummary),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
