import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../apps_controller.dart';
import '../data/app_info.dart';

const double _iconSize = 52;

/// One app in the Apps grid: icon (fetched lazily on first build, cached by
/// [AppsController]) over its display name. Tap launches it (when
/// supported); secondary-tap opens the context menu.
class AppTile extends StatefulWidget {
  const AppTile({
    super.key,
    required this.controller,
    required this.app,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final AppsController controller;
  final AppInfo app;
  final VoidCallback? onTap;
  final void Function(Offset position) onSecondaryTap;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  @override
  void initState() {
    super.initState();
    // Icon extraction only exists for Android; skip the (guaranteed-null)
    // fetch on iOS so every tile doesn't churn through the icon queue for
    // nothing.
    if (widget.controller.device is AndroidDevice) {
      widget.controller.ensureIconLoaded(widget.app.packageName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final iconBytes = widget.controller.iconFor(app.packageName);
    final busy = widget.controller.isBusyWith(app.packageName);

    return Tooltip(
      message: _tooltipFor(app),
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : widget.onTap,
          onSecondaryTapUp: (details) =>
              widget.onSecondaryTap(details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _AppIcon(bytes: iconBytes, app: app),
                      if (!app.isEnabled)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.6,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      if (busy)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.scrim.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(12),
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
                ),
                const Gap(6),
                Text(
                  app.displayName,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _tooltipFor(AppInfo app) {
    final lines = [app.packageName];
    if (app.versionName != null) lines.add('Version ${app.versionName}');
    if (!app.isEnabled) lines.add('Disabled');
    return lines.join('\n');
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.bytes, required this.app});

  final Uint8List? bytes;
  final AppInfo app;

  @override
  Widget build(BuildContext context) {
    final iconBytes = bytes;
    if (iconBytes == null) return _FallbackIcon(app: app);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        iconBytes,
        width: _iconSize,
        height: _iconSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _FallbackIcon(app: app),
      ),
    );
  }
}

/// Shown while an icon hasn't resolved yet (still fetching, unavailable, or
/// iOS with no extraction support at all): a colored initial, the color
/// picked deterministically from the package name so the same app always
/// gets the same tile across sessions.
class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({required this.app});

  final AppInfo app;

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
      width: _iconSize,
      height: _iconSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _palette[hash % _palette.length],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
