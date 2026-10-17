import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';

class const RailButton({
  super.key,
  required this.icon,
  required this.label,
  required this.isActive,
  required this.tooltip,
  required this.onTap,
  this.enabled = true,
  this.busy = false,
}) extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  /// Spins a progress ring around the icon — for a long-running action the
  /// button started, such as an app install.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        animationDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: SystemMouseCursors.click,
          splashColor: colorScheme.primary.withValues(alpha: 0.24),
          highlightColor: colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: context.scaled(6),
              horizontal: context.scaled(8),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  // The ring spills 3px into the padding, so a busy button
                  // keeps its height and the rail doesn't shift. The box
                  // follows the zoom like the icon does, so a zoomed icon
                  // doesn't spill over the label.
                  SizedBox.square(
                    dimension: context.scaled(22),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (busy)
                          Positioned.fill(
                            left: -3,
                            top: -3,
                            right: -3,
                            bottom: -3,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                              backgroundColor: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                        Icon(icon, size: busy ? 14 : 22, color: foreground),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 11, color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
