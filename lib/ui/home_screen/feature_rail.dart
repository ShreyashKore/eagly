import 'package:flutter/material.dart';

import '../../session/device_session_controller.dart';

/// Far-left vertical rail listing the features available for a device. Logs is
/// always open; Mirror toggles its pane open/closed alongside Logs.
class FeatureRail extends StatelessWidget {
  const FeatureRail({super.key, required this.session});

  final DeviceSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return Container(
          width: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            spacing: 8,
            children: [
              const SizedBox(height: 8),
              _RailButton(
                icon: Icons.article_outlined,
                label: 'Logs',
                isActive: true,
                tooltip: 'Logs',
                onTap: null,
              ),
              _RailButton(
                icon: Icons.mobile_screen_share,
                label: 'Mirror',
                isActive: session.isMirrorOpen,
                enabled: session.canMirror || session.isMirrorOpen,
                tooltip: session.canMirror
                    ? (session.isMirrorOpen ? 'Hide mirror' : 'Open mirror')
                    : 'Screen mirror supports connected Android devices',
                onTap: session.canMirror || session.isMirrorOpen
                    ? session.toggleMirror
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
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
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? colorScheme.primaryContainer.withValues(alpha: 1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
