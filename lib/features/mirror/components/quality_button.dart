import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../mirror_controller.dart';

/// Compact popup that switches the mirror's encoder quality preset.
class QualityButton extends StatelessWidget {
  const QualityButton({super.key, required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<MirrorQuality>(
      tooltip: 'Video quality (${controller.mirrorQuality.label})',
      icon: const Icon(Icons.high_quality_outlined, size: 18),
      initialValue: controller.mirrorQuality,
      onSelected: controller.setQuality,
      itemBuilder: (context) => [
        for (final quality in MirrorQuality.values)
          PopupMenuItem<MirrorQuality>(
            value: quality,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: quality == controller.mirrorQuality
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
                const Gap(10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(quality.label, style: theme.textTheme.bodyMedium),
                    Text(
                      quality.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
