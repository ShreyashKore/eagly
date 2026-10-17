import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../../../presentation/theme/app_theme.dart';

/// Single `label: value` info row with a leading icon.
class WirelessDetailRow extends StatelessWidget {
  const WirelessDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const Gap(8),
          // The label names the value; the value is what was asked for.
          Text(
            '$label: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: context.eaglyTheme.secondaryTextColor,
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
