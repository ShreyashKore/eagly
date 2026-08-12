import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'step_list.dart';

class IosGuidance extends StatelessWidget {
  const IosGuidance({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: theme.colorScheme.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(20),
              StepList(steps: steps),
            ],
          ),
        ),
      ),
    );
  }
}
