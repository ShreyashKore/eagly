import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/hover_builder.dart';

/// Header-styled accent pill mirroring the other header actions, tinted with the
/// primary color so an available update reads as a gentle call to action.
class const UpdatePill({
  super.key,
  required final String label,
  required final String tooltip,
  final IconData? icon,
  final bool busy = false,
  final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onPrimaryContainer;

    return Tooltip(
      message: tooltip,
      child: HoverBuilder(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(
                alpha: hovered && onTap != null ? 1 : 0.75,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 15, color: foreground),
                const Gap(6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
