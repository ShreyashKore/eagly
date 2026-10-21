import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/saved_file_snack_bar.dart';
import '../../flutter_scrcpy/flutter_scrcpy.dart';
import '../ios/ios_mirror_session.dart';
import '../mirror_controller.dart';
import '../services/capture_storage.dart';

/// Vertical strip on the pane's right edge: session actions (screenshot,
/// record, rotate, quality) at the top, then device hardware/navigation keys.
/// An iPhone gets its own buttons and no clipboard sync, and records only
/// with live video (macOS).
class const MirrorControlStrip({
  super.key,
  required final MirrorController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.isScreenMirrorRunning;
    final controlEnabled = running && controller.hasControl;
    final recording = controller.isRecording;
    final isIos = controller.device is IosDevice;
    final ios = controller.iosMirror;

    Widget keyButton(IconData icon, String tooltip, ScrcpyKey key) {
      return AppIconButton(
        tooltip: tooltip,
        iconSize: 16,
        onPressed: controlEnabled ? () => controller.handleKey(key) : null,
        icon: icon,
      );
    }

    Widget iosButton(IconData icon, String tooltip, IosButton button) {
      return AppIconButton(
        tooltip: tooltip,
        iconSize: 16,
        onPressed: controlEnabled
            ? () => controller.pressIosButton(button)
            : null,
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
              recording
                  ? 'Stop recording'
                  : isIos && running && !controller.canRecord
                  ? 'Recording needs live video, which only macOS has'
                  : 'Record screen',
              () => recording
                  ? _stopRecording(context)
                  : _startRecording(context),
              enabled: controller.canRecord,
              color: recording ? theme.colorScheme.error : null,
            ),
            actionButton(
              Icons.screen_rotation_outlined,
              isIos
                  ? 'Rotate device (apps that can turn follow)'
                  : 'Rotate device',
              () => _rotate(context),
              enabled: isIos ? (ios?.canRotate ?? false) : running,
            ),
            const Gap(8),
            divider(),
            const Gap(8),
            actionButton(
              Icons.content_paste,
              'Paste clipboard to device '
              '(${Platform.isMacOS ? '⌘V' : 'Ctrl+V'} in the mirror)',
              () => _paste(context),
              enabled: controller.canPasteToDevice,
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
            if (!isIos)
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
            if (isIos) ...[
              iosButton(Icons.circle_outlined, 'Home', IosButton.home),
              iosButton(
                Icons.crop_square,
                'App switcher',
                IosButton.appSwitcher,
              ),
            ] else ...[
              keyButton(Icons.arrow_back, 'Back', ScrcpyKey.back),
              keyButton(Icons.circle_outlined, 'Home', ScrcpyKey.home),
              keyButton(Icons.crop_square, 'Overview', ScrcpyKey.appSwitch),
            ],
            const Gap(8),
            divider(),
            const Gap(8),
            if (isIos) ...[
              iosButton(Icons.volume_up, 'Volume up', IosButton.volumeUp),
              iosButton(Icons.volume_down, 'Volume down', IosButton.volumeDown),
              iosButton(Icons.lock_outline, 'Lock', IosButton.lock),
            ] else ...[
              keyButton(Icons.volume_up, 'Volume up', ScrcpyKey.volumeUp),
              keyButton(Icons.volume_down, 'Volume down', ScrcpyKey.volumeDown),
              keyButton(Icons.power_settings_new, 'Power', ScrcpyKey.power),
            ],
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
      await showSavedFileSnackBar(
        messenger,
        message: 'Screenshot saved to ${_displayPath(path)}',
        path: path,
        preview: bytes,
        previewOrigin: controller.surfaceKey.currentContext,
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
    // The screen as the recording ends, for the saved snack bar's thumbnail.
    // Taken alongside stopping, so it never holds the recording open.
    final poster = controller.captureScreenshot().then<Uint8List?>(
      (bytes) => bytes,
      onError: (_) => null,
    );
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
      await showSavedFileSnackBar(
        messenger,
        message: 'Recording saved to ${_displayPath(path)}',
        path: path,
        preview: await poster,
        previewOrigin: controller.surfaceKey.currentContext,
        previewIsVideo: true,
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
