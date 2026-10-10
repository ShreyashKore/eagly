import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../apps_controller.dart';
import '../data/app_info.dart';

/// Vertical space an [AppTile] needs for an icon of [iconSize]: padding, the
/// icon, a gap and two lines of label at [labelStyle]'s (text-scaled) height.
double appTileHeight(
  BuildContext context,
  double iconSize,
  TextStyle? labelStyle,
) {
  final fontSize = labelStyle?.fontSize ?? 12;
  final lineHeight =
      MediaQuery.textScalerOf(context).scale(fontSize) *
      (labelStyle?.height ?? 1.35);
  return 12 + iconSize + 6 + lineHeight * 2 + 2;
}

/// One app in the Apps grid (and the recently-installed row): icon over its
/// display name. Tap launches it (when supported); secondary-tap opens the
/// context menu.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.controller,
    required this.app,
    required this.iconSize,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final AppsController controller;
  final AppInfo app;
  final double iconSize;
  final VoidCallback? onTap;
  final void Function(Offset position) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = controller.isBusyWith(app.packageName);

    return Tooltip(
      message: appTooltip(app),
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          onSecondaryTapUp: (details) => onSecondaryTap(details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconView(controller: controller, app: app, size: iconSize),
                const Gap(6),
                Expanded(
                  child: Text(
                    app.displayName,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

/// Hover text shared by the grid and list: the details a tile has no room for.
String appTooltip(AppInfo app) {
  final lines = [app.packageName];
  if (app.versionName != null) lines.add('Version ${app.versionName}');
  if (app.isSystemApp) lines.add('System app');
  if (!app.isEnabled) lines.add('Disabled');
  return lines.join('\n');
}

/// An app's icon at [size], with the disabled and busy overlays. Fetches the
/// icon lazily (cached by [AppsController]) the first time it is built.
class AppIconView extends StatefulWidget {
  const AppIconView({
    super.key,
    required this.controller,
    required this.app,
    required this.size,
  });

  final AppsController controller;
  final AppInfo app;
  final double size;

  @override
  State<AppIconView> createState() => _AppIconViewState();
}

class _AppIconViewState extends State<AppIconView> {
  @override
  void initState() {
    super.initState();
    // Icon extraction only exists for Android; skip the (guaranteed-null)
    // fetch on iOS so every tile doesn't churn through the icon queue for
    // nothing.
    if (widget.controller.device is AndroidDevice) {
      widget.controller.ensureIconLoaded(widget.app);
    }
  }

  @override
  void didUpdateWidget(covariant AppIconView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refresh replaces the app list with new instances; hand the new one to
    // the controller so an updated/reinstalled app re-enters the fetch queue.
    if (widget.controller.device is AndroidDevice &&
        !identical(widget.app, oldWidget.app)) {
      widget.controller.ensureIconLoaded(widget.app);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final size = widget.size;
    final radius = BorderRadius.circular(size * 0.23);
    final busy = widget.controller.isBusyWith(app.packageName);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AppIcon(
            bytes: widget.controller.iconFor(app.packageName),
            app: app,
            size: size,
            radius: radius,
          ),
          if (!app.isEnabled)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.6),
                  borderRadius: radius,
                ),
              ),
            ),
          if (busy)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.scrim.withValues(alpha: 0.45),
                  borderRadius: radius,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.bytes,
    required this.app,
    required this.size,
    required this.radius,
  });

  final Uint8List? bytes;
  final AppInfo app;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final iconBytes = bytes;
    final fallback = _FallbackIcon(app: app, size: size, radius: radius);
    if (iconBytes == null) return fallback;
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: radius,
      child: Image.memory(
        iconBytes,
        width: size,
        height: size,
        cacheWidth: decodeSize,
        cacheHeight: decodeSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

/// Shown while an icon hasn't resolved yet (still fetching, unavailable, or
/// iOS with no extraction support at all): a colored initial, the color
/// picked deterministically from the package name so the same app always
/// gets the same tile across sessions.
class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({
    required this.app,
    required this.size,
    required this.radius,
  });

  final AppInfo app;
  final double size;
  final BorderRadius radius;

  static const List<Color> _palette = [
    Color(0xFF5B8DEF),
    Color(0xFF9C6ADE),
    Color(0xFFE0637A),
    Color(0xFFE3A008),
    Color(0xFF34B27A),
    Color(0xFF37BFCB),
    Color(0xFFEF7D5B),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = app.displayName.trim();
    final letter = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    final hash = app.packageName.codeUnits.fold<int>(
      0,
      (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _palette[hash % _palette.length],
        borderRadius: radius,
      ),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}
