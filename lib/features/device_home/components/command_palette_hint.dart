import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../app_menu/intents.dart';
import '../../../app_menu/shortcuts.dart';
import '../../../command_palette/shortcut_label.dart';

/// Opens the global command palette — surfaced here so its shortcut is
/// discoverable from the device's landing screen.
class CommandPaletteHint extends StatelessWidget {
  const CommandPaletteHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => Actions.invoke(context, const OpenCommandPaletteIntent()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const Gap(6),
              Flexible(
                child: Text(
                  'Command Palette',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Gap(8),
              Text(
                describeShortcut(kCommandPaletteShortcut),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
