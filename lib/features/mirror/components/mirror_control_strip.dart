import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../mirror_controller.dart';

/// Vertical strip on the pane's right edge: session actions (screenshot,
/// record, rotate, quality) at the top, then device hardware/navigation keys.
class MirrorControlStrip extends StatelessWidget {
  const MirrorControlStrip({super.key, required this.controller});

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
            actionButton(
              Icons.content_paste,
              'Paste clipboard to device',
              () => _paste(context),
              enabled: controlEnabled,
            ),
            IconButton(
              tooltip: controller.clipboardSyncEnabled
                  ? 'Device clipboard sync: on'
                  : 'Device clipboard sync: off',
              iconSize: 16,
              color: controller.clipboardSyncEnabled
                  ? theme.colorScheme.primary
                  : null,
              onPressed: () => controller.setClipboardSyncEnabled(
                !controller.clipboardSyncEnabled,
              ),
              icon: Icon(
                controller.clipboardSyncEnabled
                    ? Icons.sync
                    : Icons.sync_disabled,
              ),
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

  Future<void> _paste(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.pasteFromClipboard();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Paste failed: $error')));
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
