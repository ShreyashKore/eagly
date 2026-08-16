import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../data/utility_command.dart';

/// One dense row in the utilities list: icon, label + description, and a
/// trailing affordance that says what a click does — open a parameter dialog,
/// ask for confirmation, or run straight away.
class UtilityTile extends StatelessWidget {
  const UtilityTile({
    super.key,
    required this.command,
    required this.preview,
    required this.isRunning,
    required this.enabled,
    required this.onTap,
  });

  final UtilityCommand command;

  /// The command line this tile would run, shown as a tooltip.
  final String? preview;
  final bool isRunning;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destructive = command.confirmation != null;
    final iconColor = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(command.icon, size: 18, color: iconColor),
          ),
          const Gap(6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.label,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(1),
                Text(
                  command.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(8),
          Icon(
            command.needsInput
                ? Icons.tune
                : destructive
                ? Icons.warning_amber_rounded
                : Icons.play_arrow_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );

    return Tooltip(
      message: preview ?? command.description,
      waitDuration: const Duration(milliseconds: 600),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: enabled ? onTap : null, child: row),
        ),
      ),
    );
  }
}
