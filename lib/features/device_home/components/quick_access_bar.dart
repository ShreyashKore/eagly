import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import 'home_primitives.dart';

/// The feature launcher strip — every pane the app offers for this device,
/// kept above the fold so a new user can see what Eagly does at a glance.
///
/// The tiles reflow with the window: a single row while every tile can still
/// hold its sublabel, then multiple rows, then a compact icon+label form once
/// even two full tiles no longer fit.
class QuickAccessBar extends StatelessWidget {
  const QuickAccessBar({super.key, required this.session});

  final DeviceSessionController session;

  static const _gap = 10.0;

  /// Width a tile needs for the label/sublabel stack to stay readable.
  static const _fullTileWidth = 178.0;

  /// Width a compact (icon + label) tile needs.
  static const _compactTileWidth = 116.0;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final isAndroid = s.platform == DevicePlatform.android;

    // Which tiles exist depends on the platform; whether they are *enabled*
    // depends on the connection — a disconnected device keeps the launcher
    // in place (greyed) instead of collapsing it to a single button.
    final specs = <_ShortcutSpec>[
      _ShortcutSpec(
        icon: Icons.article_outlined,
        label: 'Logs',
        sublabel: 'Live logcat & syslog',
        accelerator: acceleratorLabel('R'),
        isActive: s.isLogsOpen,
        onTap: s.toggleLogs,
      ),
      if (isAndroid)
        _ShortcutSpec(
          icon: Icons.mobile_screen_share_outlined,
          label: 'Mirror',
          sublabel: 'Control the screen',
          isActive: s.isMirrorOpen,
          onTap: s.canMirror ? s.toggleMirror : null,
        ),
      if (!isAndroid)
        _ShortcutSpec(
          icon: Icons.bug_report_outlined,
          label: 'Crashes',
          sublabel: 'Crash reports',
          isActive: s.isCrashReportsOpen,
          onTap: s.canReadCrashReports ? s.toggleCrashReports : null,
        ),
      _ShortcutSpec(
        icon: Icons.folder_open_outlined,
        label: 'Files',
        sublabel: 'Browse & transfer',
        isActive: s.isFilesOpen,
        onTap: s.canManageFiles ? s.toggleFiles : null,
      ),
      _ShortcutSpec(
        icon: Icons.apps_outlined,
        label: 'Apps',
        sublabel: 'Installed packages',
        isActive: s.isAppsOpen,
        onTap: s.canManageApps ? s.toggleApps : null,
      ),
      if (s.canRunUtilities)
        _ShortcutSpec(
          icon: Icons.handyman_outlined,
          label: 'Utilities',
          sublabel: 'Run device commands',
          isActive: s.isUtilitiesOpen,
          onTap: s.toggleUtilities,
        ),
      if (s.canUseTerminal)
        _ShortcutSpec(
          icon: Icons.terminal_outlined,
          label: 'Terminal',
          sublabel: 'Type adb / idevice commands',
          isActive: s.isTerminalOpen,
          onTap: s.toggleTerminal,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int fits(double tileWidth) =>
            ((constraints.maxWidth + _gap) ~/ (tileWidth + _gap))
                .clamp(1, specs.length)
                .toInt();

        // Full tiles are only worth keeping while at least two fit per row;
        // below that the sublabels would ellipsise into noise anyway.
        final fullColumns = fits(_fullTileWidth);
        final compact = fullColumns < 2 && specs.length > 1;
        final columns = compact ? fits(_compactTileWidth) : fullColumns;

        final rows = <Widget>[];
        for (var start = 0; start < specs.length; start += columns) {
          final end = (start + columns).clamp(0, specs.length);
          rows.add(
            Row(
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) const Gap(_gap),
                  Expanded(
                    child: i < end
                        // Empty slots keep the trailing row's tiles the same
                        // width as the rows above.
                        ? _ShortcutTile(spec: specs[i], compact: compact)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Gap(_gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// The data behind one launcher tile — kept separate from the widget so the
/// bar can decide between the full and compact rendering after layout.
class _ShortcutSpec {
  const _ShortcutSpec({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isActive,
    required this.onTap,
    this.accelerator,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool isActive;

  /// `null` disables the tile — the feature needs a connected device.
  final VoidCallback? onTap;
  final String? accelerator;
}

class _ShortcutTile extends StatefulWidget {
  const _ShortcutTile({required this.spec, required this.compact});

  final _ShortcutSpec spec;

  /// Drops the sublabel and the accelerator cap, and tightens the padding.
  final bool compact;

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    final active = spec.isActive;
    final enabled = spec.onTap != null;
    final compact = widget.compact;
    final accent = theme.colorScheme.primary;
    final borderColor = active
        ? accent.withValues(alpha: 0.45)
        : _hovered
        ? theme.colorScheme.outline
        : theme.colorScheme.outlineVariant;
    final iconBoxSize = compact ? 28.0 : 32.0;

    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: spec.onTap,
            child: Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(9, 9, 9, 9)
                  : const EdgeInsets.fromLTRB(12, 11, 10, 11),
              child: Row(
                children: [
                  Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      color: active
                          ? accent.withValues(alpha: 0.16)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      spec.icon,
                      size: 17,
                      color: active
                          ? accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Gap(compact ? 8 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          spec.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!compact)
                          Text(
                            spec.sublabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!compact && spec.accelerator != null && enabled) ...[
                    const Gap(6),
                    KeyCap(label: spec.accelerator!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!enabled) {
      return Tooltip(
        message: 'Reconnect the device to use ${spec.label}',
        child: Opacity(opacity: 0.45, child: tile),
      );
    }
    // Compact tiles drop the sublabel, so it moves into a tooltip.
    if (compact) return Tooltip(message: spec.sublabel, child: tile);
    return tile;
  }
}
