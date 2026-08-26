import 'package:flutter/material.dart';

class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

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
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Icon(icon, size: 22, color: foreground),
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
