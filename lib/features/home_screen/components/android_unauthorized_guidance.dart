import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'step_list.dart';

class AndroidUnauthorizedGuidance extends StatelessWidget {
  const AndroidUnauthorizedGuidance({super.key});

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
                  Icon(Icons.usb, size: 32, color: theme.colorScheme.primary),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Allow USB Debugging',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Text(
                'Your Android device is asking for permission to allow USB '
                'debugging from this computer.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(20),
              StepList(
                steps: const [
                  'Check your Android device screen',
                  'Tap "Allow" on the "Allow USB debugging?" dialog',
                  'Optionally check "Always allow from this computer"',
                  'If the dialog has dismissed, disconnect and reconnect '
                      'the USB cable',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
