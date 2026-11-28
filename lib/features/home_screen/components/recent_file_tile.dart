import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/hover_builder.dart';
import '../../../presentation/theme/platform_look.dart';
import '../../../utils/utils.dart';

/// A recently opened log file on the home page: one quiet row with the file
/// name (its full path in the tooltip) and, on hover, a button that drops it
/// from the list.
class const RecentFileTile({
  super.key,
  required final String path,
  required final VoidCallback onOpen,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(PlatformLook.controlRadius);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => Tooltip(
        message: path,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: hovered
              ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        extractFileName(path),
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Kept in the layout so the row doesn't shift on hover.
                    Opacity(
                      opacity: hovered ? 1 : 0,
                      child: AppIconButton(
                        tooltip: 'Remove from recent',
                        iconSize: 14,
                        onPressed: onRemove,
                        icon: Icons.close,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
