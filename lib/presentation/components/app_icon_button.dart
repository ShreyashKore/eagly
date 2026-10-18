import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's one icon-only button. Use it instead of Material's [IconButton]
/// (a test keeps `lib/` free of those).
///
/// Material's button sizes its box from a theme-wide min/max, while icons
/// follow the app zoom (`IconThemeData.applyTextScaling`). Once a zoomed icon
/// outgrows the clamped box the glyph paints from the box's top-left corner
/// and drifts right and down. This button instead sizes a square from
/// [iconSize] + [padding], scales *that* with the zoom too
/// (`BuildContext.scaled`), and centres the icon in it — so the icon sits in
/// the middle at every zoom level and every call site gets the same box.
///
/// Built in: a tooltip, the click cursor, hover / pressed / focus highlights,
/// a focus ring while navigating by keyboard, activation with Enter or Space,
/// button semantics, a [busy] spinner, a tinted [isActive] state, and smooth
/// transitions when the icon or its colour changes.
class const AppIconButton({
  super.key,
  final IconData? icon,

  /// Custom content in place of [icon] (e.g. an icon with a badge). It is
  /// centred in the same box and inherits the button's icon colour and size.
  /// It updates in place across rebuilds; give it a new [Key] to cross-fade
  /// to different content the way a new [icon] does.
  final Widget? child,
  final String? tooltip,

  /// `null` disables the button: it is dimmed, ignores taps and is skipped
  /// by keyboard focus traversal.
  final VoidCallback? onPressed,

  /// Toggle-style buttons: tints the background and the icon.
  final bool isActive = false,

  /// Shows a spinner in place of the icon and ignores taps.
  final bool busy = false,
  final double iconSize = defaultIconSize,
  final double padding = defaultPadding,

  /// Foreground override for an enabled, inactive button.
  final Color? color,
  final FocusNode? focusNode,
  final bool autofocus = false,

  /// Cursor over an enabled button; the click cursor when null. A button
  /// that is also a drag handle shows the grab cursor instead.
  final MouseCursor? mouseCursor,
}) extends StatefulWidget {
  this
    : assert(
        (icon == null) != (child == null),
        'Pass exactly one of icon or child.',
      );

  /// Icon size of a standard button, before zoom.
  static const double defaultIconSize = 18;

  /// Space between the icon and the edge of the highlight, before zoom.
  static const double defaultPadding = 6;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null && !widget.busy;
    final foreground = widget.onPressed == null
        ? cs.onSurface.withValues(alpha: 0.38)
        : widget.isActive
        ? cs.primary
        : widget.color ?? cs.onSurfaceVariant;
    final radius = BorderRadius.circular(context.scaled(8));
    final showFocusRing =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    Widget content;
    if (widget.busy) {
      final spinner = widget.iconSize - 2;
      content = SizedBox.square(
        key: const ValueKey('busy'),
        dimension: context.scaled(spinner),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: widget.color ?? cs.primary,
        ),
      );
    } else {
      // A fresh colour tween per icon, so the switcher below cross-fades
      // the old icon out while this animates the new one's colour. A [child]
      // is keyed by its own key, not by the widget: callers rebuild it on
      // every frame they rebuild, and a widget only equals itself, so keying
      // by it would replay the cross-fade on each rebuild.
      content = TweenAnimationBuilder<Color?>(
        key: ValueKey<Object?>(widget.icon ?? widget.child!.key),
        duration: const Duration(milliseconds: 250),
        tween: ColorTween(end: foreground),
        builder: (_, color, child) => IconTheme.merge(
          data: IconThemeData(size: widget.iconSize, color: color),
          child: child!,
        ),
        child: widget.child ?? Icon(widget.icon),
      );
    }

    // Its own transparent Material, so the ink has somewhere to paint even
    // in an overlay or a bare Stack.
    Widget button = Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: enabled,
          onFocusChange: (focused) => setState(() => _focused = focused),
          mouseCursor: enabled
              ? widget.mouseCursor ?? SystemMouseCursors.click
              : MouseCursor.defer,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: context.scaled(widget.iconSize + widget.padding * 2),
            height: context.scaled(widget.iconSize + widget.padding * 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? cs.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: showFocusRing ? cs.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.72,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}
