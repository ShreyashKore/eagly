import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';

/// One destination of the [FeatureRail]. Its fill, outline, colours and icon
/// all animate between states, so the rail reads as one moving piece rather
/// than a set of buttons that flip.
class const RailButton({
  super.key,
  required final IconData icon,
  required final String label,
  required final bool isActive,
  required final String tooltip,
  required final VoidCallback? onTap,

  /// Shown instead of [icon] while [isActive] — usually the filled variant.
  final IconData? activeIcon,

  /// Open, but not on screen: a pane kept alive underneath Home. Drawn as an
  /// outline rather than a fill, so it reads as "still there" without
  /// competing with the section that actually has the focus.
  final bool parked = false,
  final bool enabled = true,

  /// Spins a progress ring around the icon — for a long-running action the
  /// button started, such as an app install.
  final bool busy = false,
}) extends StatelessWidget {
  static const _motion = Duration(milliseconds: 140);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final motion = (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : _motion;
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isActive
        ? colorScheme.primary
        : parked
        ? colorScheme.primary.withValues(alpha: 0.8)
        : colorScheme.onSurfaceVariant;
    final shownIcon = isActive ? (activeIcon ?? icon) : icon;
    final iconSize = busy ? 14.0 : 22.0;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? colorScheme.primaryContainer : Colors.transparent,
        // The side is always there, only its colour changes, so the outline
        // fades in and out rather than popping.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            width: 1.2,
            color: colorScheme.primary.withValues(
              alpha: parked && enabled ? 0.45 : 0,
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        animationDuration: motion,
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
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: foreground),
                duration: motion,
                curve: Curves.easeOut,
                builder: (context, color, _) => Column(
                  mainAxisSize: MainAxisSize.min,
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
                          AnimatedSwitcher(
                            duration: motion,
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween(
                                      begin: 0.7,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Icon(
                              shownIcon,
                              key: ValueKey((shownIcon, iconSize)),
                              size: iconSize,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
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
