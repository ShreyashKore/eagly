import 'package:flutter/material.dart';

/// An icon button for the toolbar with smooth transitions for all state
/// changes:
/// - Icon swap (e.g. play → restart): cross-fade + scale via [AnimatedSwitcher].
/// - Color change (enabled ↔ disabled, active ↔ inactive): smooth tween via
///   [TweenAnimationBuilder].
/// - Background tint (active state): [AnimatedContainer].
class ToolbarIconButton extends StatelessWidget {
  const ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// When true, renders with a tinted rounded background.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final targetColor = isActive
        ? cs.primary
        : enabled
        ? cs.onSurfaceVariant
        : cs.onSurface.withValues(alpha: 0.38);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          // AnimatedSwitcher detects icon changes (via ValueKey) and
          // cross-fades + scales the old icon out / new icon in.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.72, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            // TweenAnimationBuilder smoothly interpolates the icon color
            // between state changes (enabled/disabled, active/inactive).
            // Keying by icon ensures a fresh tween whenever the icon itself
            // changes (the AnimatedSwitcher handles that transition instead).
            child: TweenAnimationBuilder<Color?>(
              key: ValueKey(icon),
              duration: const Duration(milliseconds: 250),
              tween: ColorTween(end: targetColor),
              builder: (_, color, __) =>
                  Icon(icon, size: 20, color: color ?? targetColor),
            ),
          ),
        ),
      ),
    );
  }
}
