import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/feature_view.dart';
import '../flutter_scrcpy/flutter_scrcpy.dart';
import 'mirror_controller.dart';

/// Screen-mirror feature pane. Renders the live texture + controls, driven by a
/// [MirrorController]. [onClose] hides the pane (handled by the device screen).
class MirrorFeatureView extends FeatureView {
  const MirrorFeatureView({
    super.key,
    required this.controller,
    required VoidCallback onClose,
  }) : super(onClose: onClose);

  final MirrorController controller;

  @override
  State<MirrorFeatureView> createState() => _MirrorFeatureViewState();
}

class _MirrorFeatureViewState extends FeatureViewState<MirrorFeatureView> {
  MirrorController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  @override
  Widget buildContent(BuildContext context) {
    return FeaturePane(
      header: FeatureViewHeader(
        title: 'Screen mirror',
        closeTooltip: 'Close mirror pane',
        onClose: widget.onClose,
        actions: [
          IconButton(
            tooltip: controller.isScreenMirrorRunning
                ? 'Stop mirror'
                : 'Start mirror',
            onPressed: controller.canStart || controller.isScreenMirrorRunning
                ? () {
                    if (controller.isScreenMirrorRunning) {
                      controller.stop();
                    } else {
                      controller.start();
                    }
                  }
                : null,
            icon: Icon(
              controller.isScreenMirrorRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow,
            ),
          ),
          _QualityButton(controller: controller),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(child: _PaneBody(controller: controller)),
          ),
          _MirrorControlStrip(controller: controller),
        ],
      ),
    );
  }
}

/// Vertical strip on the pane's right edge: session actions (screenshot,
/// record, rotate, quality) at the top, then device hardware/navigation keys.
class _MirrorControlStrip extends StatelessWidget {
  const _MirrorControlStrip({required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.isScreenMirrorRunning;
    final controlEnabled =
        running && controller.screenMirrorSession?.control != null;
    final recording = controller.isRecording;

    Widget keyButton(IconData icon, String tooltip, ScrcpyKey key) {
      return IconButton(
        tooltip: tooltip,
        iconSize: 16,
        onPressed: controlEnabled ? () => controller.handleKey(key) : null,
        icon: Icon(icon),
      );
    }

    Widget actionButton(
      IconData icon,
      String tooltip,
      Future<void> Function() onTap, {
      bool enabled = true,
      Color? color,
    }) {
      return IconButton(
        tooltip: tooltip,
        iconSize: 16,
        color: color,
        onPressed: enabled ? () => onTap() : null,
        icon: Icon(icon),
      );
    }

    Widget divider() => Divider(
      height: 1,
      thickness: 1,
      indent: 10,
      endIndent: 10,
      color: theme.colorScheme.outlineVariant,
    );

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Gap(8),
            actionButton(
              Icons.photo_camera_outlined,
              'Screenshot',
              () => _captureScreenshot(context),
              enabled: running,
            ),
            actionButton(
              recording ? Icons.stop_circle : Icons.videocam_outlined,
              recording ? 'Stop recording' : 'Record screen',
              () => recording
                  ? _stopRecording(context)
                  : _startRecording(context),
              enabled: running,
              color: recording ? theme.colorScheme.error : null,
            ),
            actionButton(
              Icons.screen_rotation_outlined,
              'Rotate device',
              () => _rotate(context),
              enabled: running,
            ),
            const Gap(8),
            divider(),
            const Gap(8),
            keyButton(Icons.arrow_back, 'Back', ScrcpyKey.back),
            keyButton(Icons.circle_outlined, 'Home', ScrcpyKey.home),
            keyButton(Icons.crop_square, 'Overview', ScrcpyKey.appSwitch),
            const Gap(8),
            divider(),
            const Gap(8),
            keyButton(Icons.volume_up, 'Volume up', ScrcpyKey.volumeUp),
            keyButton(Icons.volume_down, 'Volume down', ScrcpyKey.volumeDown),
            keyButton(Icons.power_settings_new, 'Power', ScrcpyKey.power),
            const Gap(8),
          ],
        ),
      ),
    );
  }

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<void> _captureScreenshot(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await controller.captureScreenshot();
      if (bytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Screenshot unavailable.')),
        );
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save screenshot',
        fileName: 'screenshot-${_timestamp()}.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      if (path == null) return; // user cancelled
      final outPath = path.toLowerCase().endsWith('.png') ? path : '$path.png';
      await File(outPath).writeAsBytes(bytes);
      messenger.showSnackBar(
        SnackBar(content: Text('Screenshot saved to $outPath')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Screenshot failed: $error')),
      );
    }
  }

  Future<void> _startRecording(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.startRecording();
      if (controller.isRecording) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Recording… tap again to stop.')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Recording failed: $error')),
      );
    }
  }

  Future<void> _stopRecording(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save screen recording',
      fileName: 'recording-${_timestamp()}.mp4',
      type: FileType.custom,
      allowedExtensions: ['mp4'],
    );
    try {
      if (path == null) {
        await controller.cancelRecording();
        messenger.showSnackBar(
          const SnackBar(content: Text('Recording discarded.')),
        );
        return;
      }
      final outPath = path.toLowerCase().endsWith('.mp4') ? path : '$path.mp4';
      messenger.showSnackBar(
        const SnackBar(content: Text('Saving recording…')),
      );
      await controller.stopRecording(outPath);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Recording saved to $outPath')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Recording failed: $error')),
      );
    }
  }

  Future<void> _rotate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.rotate();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Rotate failed: $error')));
    }
  }
}

/// Compact popup that switches the mirror's encoder quality preset.
class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<MirrorQuality>(
      tooltip: 'Video quality (${controller.mirrorQuality.label})',
      icon: const Icon(Icons.high_quality_outlined, size: 18),
      initialValue: controller.mirrorQuality,
      onSelected: controller.setQuality,
      itemBuilder: (context) => [
        for (final quality in MirrorQuality.values)
          PopupMenuItem<MirrorQuality>(
            value: quality,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: quality == controller.mirrorQuality
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
                const Gap(10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(quality.label, style: theme.textTheme.bodyMedium),
                    Text(
                      quality.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = controller.device;
    final session = controller.screenMirrorSession;

    // Display the live texture once the mirror is running.
    if (session != null && controller.isScreenMirrorRunning) {
      final aspectRatio = session.height > 0
          ? session.width / session.height
          : 9 / 16;
      return ScrcpyView(
        textureId: session.textureId,
        aspectRatio: aspectRatio,
        onTouch: controller.handleTouch,
      );
    }

    final (
      :icon,
      :title,
      :description,
    ) = switch (controller.screenMirrorState) {
      ScreenMirrorState.starting => (
        icon: Icons.hourglass_top_rounded,
        title: 'Starting mirror',
        description: 'Opening scrcpy for ${device.displayName}.',
      ),
      ScreenMirrorState.running => (
        icon: Icons.cast_connected_rounded,
        title: 'Mirror running',
        description: 'scrcpy is controlling ${device.displayName}.',
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
        title: 'Ready to mirror',
        description: 'Launch scrcpy for ${device.displayName}.',
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
                ? () => controller.stop()
                : controller.canStart
                ? () => controller.start()
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
