import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../presentation/components/context_menu.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/log_framework.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

/// One chip per framework whose lines the captured logs show (Flutter, React
/// Native, Unity…; see [LogFramework]), for isolating or hiding them in one
/// click. Nothing is drawn until a framework is detected or has a filter set,
/// so apps built without one never see the chips. Once shown, a chip stays
/// until the tab is cleared or a fresh capture starts, even after the app
/// stops logging: a chip must not vanish under the cursor.
///
/// The chips carry the framework's official logo, are framework-coloured and
/// outlined, unlike the tinted filter pills, so they read as quick toggles
/// rather than conditions. A click toggles *show only* (a check mark); the
/// right-click (or long-press) menu can hide the framework's lines instead
/// (the logo dimmed and struck through), or clear the filter. With
/// [compact], or once more than [labelledUpTo] frameworks show, a chip shows
/// only its logo and names itself in the tooltip; the label slides away
/// rather than snapping.
class const LogFrameworkChips({
  super.key,
  required final LogFilterController controller,
  final bool compact = false,
}) extends StatelessWidget {
  /// The most chips drawn with their label; past it, logos only.
  static const int labelledUpTo = 2;

  /// How long a label takes to slide in or out when the chips switch between
  /// logo and label and logo only; none with reduced motion.
  @visibleForTesting
  static Duration labelMotion = const Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final frameworks = controller.visibleFrameworks;
        if (frameworks.isEmpty) return const SizedBox.shrink();
        final compact = this.compact || frameworks.length > labelledUpTo;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, framework) in frameworks.indexed) ...[
              if (index > 0) const SizedBox(width: 6),
              _FrameworkChip(
                key: ValueKey(framework),
                framework: framework,
                mode: controller.frameworkMode(framework),
                compact: compact,
                onModeChanged: (mode) =>
                    controller.setFrameworkMode(framework, mode),
              ),
            ],
          ],
        );
      },
    );
  }
}

class const _FrameworkChip({
  super.key,
  required final LogFramework framework,
  required final FrameworkFilterMode? mode,
  required final bool compact,
  required final ValueChanged<FrameworkFilterMode?> onModeChanged,
}) extends StatefulWidget {
  @override
  State<_FrameworkChip> createState() => _FrameworkChipState();
}

class _FrameworkChipState extends State<_FrameworkChip> {
  bool _focused = false;

  LogFramework get _framework => widget.framework;

  void _toggle() => widget.onModeChanged(
    widget.mode == FrameworkFilterMode.only ? null : FrameworkFilterMode.only,
  );

  Future<void> _showMenu(Offset position) async {
    final label = _framework.label;
    final mode = widget.mode;
    final result = await showMenu<_ChipAction>(
      context: context,
      position: menuPositionAt(position),
      items: [
        PopupMenuItem(
          value: _ChipAction.only,
          enabled: mode != FrameworkFilterMode.only,
          child: MenuRow(Icons.filter_alt_outlined, 'Show only $label logs'),
        ),
        PopupMenuItem(
          value: _ChipAction.hide,
          enabled: mode != FrameworkFilterMode.hide,
          child: MenuRow(Icons.visibility_off_outlined, 'Hide $label logs'),
        ),
        if (mode != null)
          PopupMenuItem(
            value: _ChipAction.clear,
            child: MenuRow(Icons.close, 'Clear $label filter'),
          ),
      ],
    );
    if (!mounted || result == null) return;
    widget.onModeChanged(switch (result) {
      _ChipAction.only => FrameworkFilterMode.only,
      _ChipAction.hide => FrameworkFilterMode.hide,
      _ChipAction.clear => null,
    });
  }

  /// Opens the menu under the chip, for a long-press, which has no position.
  void _showMenuBelow() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    unawaited(_showMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero))));
  }

  String get _tooltip {
    final label = _framework.label;
    return switch (widget.mode) {
      FrameworkFilterMode.only =>
        'Showing only $label logs. Click to show all; right-click for more.',
      FrameworkFilterMode.hide =>
        'Hiding $label logs. Click to show only them; right-click for more.',
      null => 'Click to show only $label logs; right-click to hide them.',
    };
  }

  String get _semanticsLabel {
    final label = _framework.label;
    return switch (widget.mode) {
      FrameworkFilterMode.only => '$label logs: showing only these',
      FrameworkFilterMode.hide => '$label logs: hidden',
      null => '$label logs: not filtered',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = context.eaglyTheme.frameworkColor(_framework);
    final mode = widget.mode;
    final motion = (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : LogFrameworkChips.labelMotion;
    final showFocusRing =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final radius = BorderRadius.circular(context.filterPillHeight / 2);
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: accent,
      decoration: mode == FrameworkFilterMode.hide
          ? TextDecoration.lineThrough
          : null,
      decorationColor: accent,
    );

    return Tooltip(
      message: widget.compact ? '${_framework.label}: $_tooltip' : _tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        toggled: mode == FrameworkFilterMode.only,
        label: _semanticsLabel,
        excludeSemantics: true,
        child: Padding(
          // Centres the pill-height chip on the filter row's taller controls.
          padding: EdgeInsets.symmetric(
            vertical:
                (context.filterControlHeight - context.filterPillHeight) / 2,
          ),
          child: Material(
            color: mode == FrameworkFilterMode.only
                ? accent.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: showFocusRing
                    ? colors.primary
                    : accent.withValues(alpha: mode == null ? 0.55 : 0.9),
                width: showFocusRing || mode != null ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _toggle,
              onSecondaryTapUp: (details) =>
                  unawaited(_showMenu(details.globalPosition)),
              onLongPress: _showMenuBelow,
              onFocusChange: (focused) => setState(() => _focused = focused),
              hoverColor: accent.withValues(alpha: 0.08),
              splashColor: accent.withValues(alpha: 0.12),
              highlightColor: accent.withValues(alpha: 0.10),
              child: SizedBox(
                height: context.filterPillHeight,
                child: AnimatedPadding(
                  duration: motion,
                  curve: _labelCurve,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 8 : 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FrameworkLogo(
                        framework: _framework,
                        color: accent,
                        struckThrough: mode == FrameworkFilterMode.hide,
                      ),
                      _AnimatedLabel(
                        visible: !widget.compact,
                        duration: motion,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            _framework.label,
                            style: labelStyle,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                      if (mode == FrameworkFilterMode.only) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check, size: 14, color: accent),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChipAction { only, hide, clear }

const Curve _labelCurve = Curves.easeInOutCubic;

/// [child] sliding in from, or out to, its left edge as it fades, while the
/// space it takes grows or shrinks with it. Once fully out it is not built.
class const _AnimatedLabel({
  required final bool visible,
  required final Duration duration,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1.0 : 0.0),
      duration: duration,
      curve: _labelCurve,
      child: child,
      builder: (context, factor, child) {
        if (factor == 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: Opacity(opacity: factor, child: child),
          ),
        );
      },
    );
  }
}

/// A framework's official logo, [size] logical pixels square before the app
/// zoom. A monochrome logo is tinted [color]; a full-colour one
/// ([LogFramework.logoHasOwnColours], Defold) keeps its own colours. A
/// framework with no logo asset ([LogFramework.logoAsset] null) gets a glyph
/// of its own ([fallbackIcon]), so two compact chips still differ by shape.
/// [struckThrough] dims the logo and draws a slash across it, for a hidden
/// framework, keeping its shape recognisable.
class const FrameworkLogo({
  super.key,
  required final LogFramework framework,
  required final Color color,
  final double size = 16,
  final bool struckThrough = false,
}) extends StatelessWidget {
  /// The glyph drawn for a framework with no logo asset, distinct per
  /// framework; null for one that has a logo.
  static IconData? fallbackIcon(LogFramework framework) => switch (framework) {
    LogFramework.solar2d => Icons.wb_sunny_outlined,
    LogFramework.kivy => Icons.touch_app_outlined,
    _ => null,
  };

  /// How much of a struck-through logo shows.
  static const double _dimmedAlpha = 0.45;

  @override
  Widget build(BuildContext context) {
    final extent = context.scaled(size);
    final tint = struckThrough ? color.withValues(alpha: _dimmedAlpha) : color;
    final asset = framework.logoAsset;
    final Widget logo;
    if (asset == null) {
      logo = Icon(
        fallbackIcon(framework) ?? Icons.extension_outlined,
        size: size,
        color: tint,
      );
    } else {
      logo = SvgPicture(
        framework.logoHasOwnColours
            ? _InlineStyleSvgAssetLoader(asset)
            : SvgAssetLoader(asset),
        width: extent,
        height: extent,
        excludeFromSemantics: true,
        colorFilter: framework.logoHasOwnColours
            // dstIn keeps the logo's colours and scales its alpha.
            ? (struckThrough
                  ? ColorFilter.mode(
                      Colors.black.withValues(alpha: _dimmedAlpha),
                      BlendMode.dstIn,
                    )
                  : null)
            : ColorFilter.mode(tint, BlendMode.srcIn),
      );
    }
    if (!struckThrough) return logo;
    return CustomPaint(foregroundPainter: _SlashPainter(color), child: logo);
  }
}

/// Loads an SVG asset whose fills come from a `<style>` block, which
/// flutter_svg ignores (it would paint every path black): the CSS class rules
/// are inlined first ([inlineSvgClassStyles]). The asset itself stays
/// byte-for-byte the publisher's file.
class _InlineStyleSvgAssetLoader extends SvgAssetLoader {
  const _InlineStyleSvgAssetLoader(super.assetName);

  @override
  String provideSvg(ByteData? message) =>
      inlineSvgClassStyles(super.provideSvg(message));

  // Kept apart from a plain [SvgAssetLoader] of the same asset in the cache.
  @override
  SvgCacheKey cacheKey(BuildContext? context) {
    final key = super.cacheKey(context);
    return SvgCacheKey(
      keyData: (#inlineStyle, key.keyData),
      theme: key.theme,
      colorMapper: key.colorMapper,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _InlineStyleSvgAssetLoader && super == other;

  @override
  int get hashCode => Object.hash(#inlineStyle, super.hashCode);
}

final _svgStyleElement = RegExp(r'<style[^>]*>([\s\S]*?)</style>');
final _cssClassRule = RegExp(r'\.([\w-]+)\s*\{([^}]*)\}');
final _svgClassAttribute = RegExp(r'\sclass="([^"]*)"');

/// [svg] with each `class="…"` attribute replaced by a `style` attribute
/// holding the declarations its `.class { … }` rules give in the `<style>`
/// blocks, which are removed. Only plain class selectors are understood, as
/// Illustrator exports them; an element must not also have its own `style`.
@visibleForTesting
String inlineSvgClassStyles(String svg) {
  final rules = <String, String>{};
  for (final block in _svgStyleElement.allMatches(svg)) {
    for (final rule in _cssClassRule.allMatches(block[1]!)) {
      rules[rule[1]!] = rule[2]!.trim();
    }
  }
  if (rules.isEmpty) return svg;
  return svg.replaceAll(_svgStyleElement, '').replaceAllMapped(
    _svgClassAttribute,
    (match) {
      final declarations = [
        for (final name in match[1]!.trim().split(RegExp(r'\s+'))) ?rules[name],
      ];
      return declarations.isEmpty
          ? match[0]!
          : ' style="${declarations.join(';')}"';
    },
  );
}

/// A diagonal stroke from the top-right to the bottom-left corner.
class _SlashPainter extends CustomPainter {
  _SlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.92, size.height * 0.08),
      Offset(size.width * 0.08, size.height * 0.92),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) => oldDelegate.color != color;
}
