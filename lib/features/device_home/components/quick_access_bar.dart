import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../session/device_session_controller.dart';

/// The feature launcher strip — every pane the app offers for this device,
/// kept above the fold so a new user can see what Eagly does at a glance.
class QuickAccessBar extends StatelessWidget {
  const QuickAccessBar({super.key, required this.session});

  final DeviceSessionController session;

  static String _accel(String key) =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘$key' : 'Ctrl+$key';

  @override
  Widget build(BuildContext context) {
    final s = session;
    final tiles = <Widget>[
      _ShortcutTile(
        icon: Icons.article_outlined,
        label: 'Logs',
        sublabel: 'Live logcat & syslog',
        accelerator: _accel('R'),
        isActive: s.isLogsOpen,
        onTap: s.toggleLogs,
      ),
      if (s.canMirror)
        _ShortcutTile(
          icon: Icons.mobile_screen_share_outlined,
          label: 'Mirror',
          sublabel: 'Control the screen',
          isActive: s.isMirrorOpen,
          onTap: s.toggleMirror,
        ),
      if (s.canReadCrashReports)
        _ShortcutTile(
          icon: Icons.bug_report_outlined,
          label: 'Crashes',
          sublabel: 'Crash reports',
          isActive: s.isCrashReportsOpen,
          onTap: s.toggleCrashReports,
        ),
      if (s.canManageFiles)
        _ShortcutTile(
          icon: Icons.folder_open_outlined,
          label: 'Files',
          sublabel: 'Browse & transfer',
          isActive: s.isFilesOpen,
          onTap: s.toggleFiles,
        ),
      if (s.canManageApps)
        _ShortcutTile(
          icon: Icons.apps_outlined,
          label: 'Apps',
          sublabel: 'Installed packages',
          isActive: s.isAppsOpen,
          onTap: s.toggleApps,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const Gap(10),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _ShortcutTile extends StatefulWidget {
  const _ShortcutTile({
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
  final VoidCallback onTap;
  final String? accelerator;

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.isActive;
    final accent = theme.colorScheme.primary;
    final borderColor = active
        ? accent.withValues(alpha: 0.45)
        : _hovered
        ? theme.colorScheme.outline
        : theme.colorScheme.outlineVariant;

    return MouseRegion(
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
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: active
                          ? accent.withValues(alpha: 0.16)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 17,
                      color: active
                          ? accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.sublabel,
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
                  if (widget.accelerator != null) ...[
                    const Gap(6),
                    KeyCap(label: widget.accelerator!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keyboard accelerator hint rendered as a small key cap.
class KeyCap extends StatelessWidget {
  const KeyCap({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
