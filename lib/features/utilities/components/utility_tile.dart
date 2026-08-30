import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';

/// One row in the utilities list: a tinted icon, the label + description, and
/// a trailing chip that spells out what clicking will do next — open a
/// parameters dialog, ask for confirmation, or run straight away. The chip is
/// the whole point of the row's right-hand side: a new user should never have
/// to click a utility to find out whether it is about to do something.
class UtilityTile extends StatefulWidget {
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
  State<UtilityTile> createState() => _UtilityTileState();
}

class _UtilityTileState extends State<UtilityTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = widget.command;
    final destructive = command.isDestructive;
    final accent = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _IconBadge(
            icon: command.icon,
            color: accent,
            isRunning: widget.isRunning,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                Text(
                  command.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(10),
          _ActionChip(command: command, highlighted: _hovered),
        ],
      ),
    );

    return Tooltip(
      message: widget.preview ?? command.description,
      waitDuration: const Duration(milliseconds: 600),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              onHover: (value) => setState(() => _hovered = value),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    required this.isRunning,
  });

  final IconData icon;
  final Color color;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: isRunning
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 17, color: color),
    );
  }
}

/// Says what the click does. Three states, in priority order: a destructive
/// command warns, a parameterised one promises a dialog, everything else runs
/// immediately.
class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.command, required this.highlighted});

  final UtilityCommand command;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;

    final (IconData icon, String label, Color color) = switch (command) {
      _ when command.isDestructive => (
        Icons.warning_amber_rounded,
        command.needsInput ? 'Set up' : 'Confirm',
        eaglyTheme.warningColor,
      ),
      _ when command.needsInput => (
        Icons.tune,
        'Options',
        theme.colorScheme.onSurfaceVariant,
      ),
      _ => (
        Icons.play_arrow_rounded,
        'Run',
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlighted ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const Gap(4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
