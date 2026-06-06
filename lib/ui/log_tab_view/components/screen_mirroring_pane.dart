import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../log_tab_controller.dart';

class ScreenMirroringPane extends StatelessWidget {
  const ScreenMirroringPane({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final LogTabController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 340,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 420),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(controller: controller, onClose: onClose),
          Expanded(
            child: Center(child: _PaneBody(controller: controller)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});

  final LogTabController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.mobile_screen_share, color: theme.colorScheme.primary),
          const Gap(8),
          Expanded(
            child: Text(
              'Screen mirror',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: controller.isScreenMirrorRunning
                ? 'Stop mirror'
                : 'Start mirror',
            onPressed:
                controller.canStartScreenMirror ||
                    controller.isScreenMirrorRunning
                ? () {
                    if (controller.isScreenMirrorRunning) {
                      controller.stopScreenMirror();
                    } else {
                      controller.startScreenMirror();
                    }
                  }
                : null,
            icon: Icon(
              controller.isScreenMirrorRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow,
            ),
          ),
          IconButton(
            tooltip: 'Close mirror pane',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.controller});

  final LogTabController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = controller.selectedDevice;

    final (
      :icon,
      :title,
      :description,
    ) = switch (controller.screenMirrorState) {
      ScreenMirrorState.starting => (
        icon: Icons.hourglass_top_rounded,
        title: 'Starting mirror',
        description: device == null
            ? 'Preparing scrcpy.'
            : 'Opening scrcpy for ${device.displayName}.',
      ),
      ScreenMirrorState.running => (
        icon: Icons.cast_connected_rounded,
        title: 'Mirror running',
        description: device == null
            ? 'scrcpy is active.'
            : 'scrcpy is controlling ${device.displayName}.',
      ),
      ScreenMirrorState.unsupported => (
        icon: Icons.phonelink_off_rounded,
        title: 'Unsupported device',
        description:
            controller.screenMirrorError ??
            'Screen mirroring is available for Android devices.',
      ),
      ScreenMirrorState.error => (
        icon: Icons.error_outline_rounded,
        title: 'Mirror unavailable',
        description:
            controller.screenMirrorError ??
            'The mirror session could not be started.',
      ),
      ScreenMirrorState.stopped => (
        icon: Icons.mobile_screen_share,
        title: device == null ? 'No device selected' : 'Ready to mirror',
        description: device == null
            ? 'Select a connected Android device.'
            : 'Launch scrcpy for ${device.displayName}.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.primary),
          const Gap(12),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(18),
          FilledButton.icon(
            onPressed: controller.isScreenMirrorRunning
                ? () => controller.stopScreenMirror()
                : controller.canStartScreenMirror
                ? () => controller.startScreenMirror()
                : null,
            icon: Icon(
              controller.isScreenMirrorRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow,
            ),
            label: Text(
              controller.isScreenMirrorRunning ? 'Stop mirror' : 'Start mirror',
            ),
          ),
        ],
      ),
    );
  }
}
