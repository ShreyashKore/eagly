import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/saved_file_snack_bar.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../mirror_controller.dart';
import '../services/capture_storage.dart';

/// Vertical strip on the pane's right edge: session actions (screenshot,
/// record, rotate, quality) at the top, then device hardware/navigation keys.
class const MirrorControlStrip({super.key, required this.controller})
    extends StatelessWidget {
  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.isScreenMirrorRunning;
    final controlEnabled =
        running && controller.screenMirrorSession?.control != null;
    final recording = controller.isRecording;

    Widget keyButton(IconData icon, String tooltip, ScrcpyKey key) {
      return AppIconButton(
        tooltip: tooltip,
        iconSize: 16,
        onPressed: controlEnabled ? () => controller.handleKey(key) : null,
        icon: icon,
      );
    }

    Widget actionButton(
      IconData icon,
      String tooltip,
      Future<void> Function() onTap, {
      bool enabled = true,
      Color? color,
    }) {
      return AppIconButton(
        tooltip: tooltip,
        iconSize: 16,
        color: color,
        onPressed: enabled ? () => onTap() : null,
        icon: icon,
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
              'Paste clipboard to device '
              '(${Platform.isMacOS ? '⌘V' : 'Ctrl+V'} in the mirror)',
              () => _paste(context),
              enabled: controlEnabled,
            ),
            AppIconButton(
              tooltip: controller.isKeyboardForwarding
                  ? 'Keyboard goes to the device — click the app to stop'
                  : 'Send keyboard to device (or click the mirror)',
              iconSize: 16,
              isActive: controller.isKeyboardForwarding,
              onPressed: controlEnabled
                  ? controller.keyboardFocusNode.requestFocus
                  : null,
              icon: controller.isKeyboardForwarding
                  ? Icons.keyboard
                  : Icons.keyboard_outlined,
            ),
            AppIconButton(
              tooltip: controller.clipboardSyncEnabled
                  ? 'Device clipboard sync: on'
                  : 'Device clipboard sync: off',
              iconSize: 16,
              isActive: controller.clipboardSyncEnabled,
              onPressed: () => controller.setClipboardSyncEnabled(
                !controller.clipboardSyncEnabled,
              ),
              icon: controller.clipboardSyncEnabled
                  ? Icons.sync
                  : Icons.sync_disabled,
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
      final path = await CaptureStorage.resolveTargetPath(
        dialogTitle: 'Save screenshot',
        prefix: 'screenshot',
        extension: 'png',
      );
      if (path == null) return; // user cancelled the save dialog
      await File(path).writeAsBytes(bytes);
      showSavedFileSnackBar(
        messenger,
        message: 'Screenshot saved to ${_displayPath(path)}',
        path: path,
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
    try {
      final path = await CaptureStorage.resolveTargetPath(
        dialogTitle: 'Save screen recording',
        prefix: 'recording',
        extension: 'mp4',
      );
      if (path == null) {
        await controller.cancelRecording();
        messenger.showSnackBar(
          const SnackBar(content: Text('Recording discarded.')),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Saving recording…')),
      );
      await controller.stopRecording(path);
      showSavedFileSnackBar(
        messenger,
        message: 'Recording saved to ${_displayPath(path)}',
        path: path,
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Recording failed: $error')),
      );
    }
  }

  /// `<folder>/<file>` — the full path is long enough to blow past the snack
  /// bar, and the tooltip there carries the rest.
  static String _displayPath(String path) {
    final separator = Platform.pathSeparator;
    final segments = path.split(separator);
    if (segments.length < 2) return path;
    return segments.sublist(segments.length - 2).join(separator);
  }

  Future<void> _paste(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await controller.pasteFromClipboard()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nothing to paste — no text copied.')),
        );
      }
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
