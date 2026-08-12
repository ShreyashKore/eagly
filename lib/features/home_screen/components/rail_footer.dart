import 'package:flutter/material.dart';

import '../../../services/eagly_info_service.dart';

/// Bottom-pinned separator and the app version, shown unobtrusively.
class RailFooter extends StatelessWidget {
  const RailFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant,
        ),
        const SizedBox(height: 6),
        Text(
          'v${EaglyInfoService.appVersion}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
