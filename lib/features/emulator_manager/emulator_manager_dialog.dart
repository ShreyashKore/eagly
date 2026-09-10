import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../data/device.dart';
import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/eagly_dialog.dart';
import '../../session/device_session_manager.dart';
import '../../utils/android_sdk_path.dart';
import '../wireless_connection/components/wireless_feedback_banner.dart';
import 'components/emulator_tile.dart';
import 'data/emulator_entry.dart';
import 'data/emulator_launch_options.dart';
import 'emulator_manager_controller.dart';

/// Presents the emulator manager.
Future<void> showEmulatorManagerDialog({
  required BuildContext context,
  required DeviceSessionManager manager,
  required ValueChanged<String> onShowSnackBar,
}) {
  return showEaglyDialog<void>(
    context: context,
    builder: (_) =>
        EmulatorManagerDialog(manager: manager, onShowSnackBar: onShowSnackBar),
  );
}

/// Lists this SDK's AVDs and starts or stops them, so launching an emulator
/// does not mean opening Android Studio.
///
/// The emulator binary belongs to the user's own SDK rather than to Eagly's
/// bundled `platform-tools`, so "no SDK here" is a first-class state of this
/// dialog and not an error.
class EmulatorManagerDialog extends StatefulWidget {
  const EmulatorManagerDialog({
    super.key,
    required this.manager,
    required this.onShowSnackBar,
    this.createController,
  });

  final DeviceSessionManager manager;
  final ValueChanged<String> onShowSnackBar;

  /// Overrides how the controller is built, handing the builder the dialog's
  /// own "an emulator booted" callback so that path stays wired.
  ///
  /// Tests pass this to keep the dialog away from the machine's real SDK;
  /// nothing in the app should. The dialog owns and disposes whatever comes
  /// back either way.
  @visibleForTesting
  final EmulatorManagerController Function(
    Future<void> Function(Device device) onEmulatorReady,
  )?
  createController;

  @override
  State<EmulatorManagerDialog> createState() => _EmulatorManagerDialogState();
}

class _EmulatorManagerDialogState extends State<EmulatorManagerDialog> {
  late final EmulatorManagerController controller =
      widget.createController?.call(_handleEmulatorReady) ??
      EmulatorManagerController(
        devicesRepository: widget.manager.repository,
        onEmulatorReady: _handleEmulatorReady,
      );

  @override
  void initState() {
    super.initState();
    unawaited(controller.start());
  }

  @override
  void dispose() {
    // Required, not optional: the controller owns a poll loop that would
    // otherwise outlive the dialog. (The wireless dialog once forgot this.)
    controller.dispose();
    super.dispose();
  }

  /// An emulator we launched has booted. Open its tab and get out of the way —
  /// reaching the device is the whole point of having started it.
  ///
  /// Only fires for a launch made from here, so an emulator that was already
  /// running when the dialog opened never steals the user's selection.
  Future<void> _handleEmulatorReady(Device device) async {
    if (!mounted) return;
    widget.manager.select(device.id);
    widget.onShowSnackBar('${device.displayName} is ready.');

    // Only when this dialog is what is actually on top. A boot finishing while
    // the user has a wipe confirmation or a start-options menu open would
    // otherwise pop *that*, cancelling something they were in the middle of.
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleLaunch(
    EmulatorEntry entry,
    EmulatorLaunchChoice choice,
  ) async {
    if (choice == EmulatorLaunchChoice.wipeData &&
        !await _confirmWipe(entry.label)) {
      return;
    }
    if (!mounted) return;

    await controller.launch(
      entry.name,
      options: switch (choice) {
        EmulatorLaunchChoice.normal => EmulatorLaunchOptions.normal,
        EmulatorLaunchChoice.coldBoot => const EmulatorLaunchOptions(
          coldBoot: true,
        ),
        EmulatorLaunchChoice.wipeData => const EmulatorLaunchOptions(
          wipeData: true,
        ),
      },
    );
  }

  Future<bool> _confirmWipe(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: const Text('Wipe data and start?'),
        content: Text(
          'Everything on $label — installed apps, accounts, files and '
          'settings — is erased before it boots. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wipe and start'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return EaglyDialog(
          title: 'Android Emulators',
          icon: Icons.phone_android_outlined,
          width: 640,
          height: 520,
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          headerActions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: controller.isLoading
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: controller.isLoading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WirelessFeedbackBanner(
                message: controller.message,
                error: controller.error,
              ),
              if (controller.message != null || controller.error != null)
                const Gap(14),
              Flexible(child: _buildBody(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final sdk = controller.sdk;

    if (sdk == null || controller.isLoading && controller.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!sdk.isReady) return _buildSdkNotice(sdk);

    if (controller.entries.isEmpty) {
      return const CenteredStateMessage(
        icon: Icons.phone_android_outlined,
        title: 'No emulators yet',
        description:
            'This SDK has no virtual devices. Create one in Android '
            'Studio’s Device Manager and it will show up here.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: controller.entries.length,
      separatorBuilder: (_, _) => const Gap(8),
      itemBuilder: (context, index) {
        final entry = controller.entries[index];
        return EmulatorTile(
          entry: entry,
          enabled: !controller.isBusy,
          onLaunch: (choice) => unawaited(_handleLaunch(entry, choice)),
          onStop: () => unawaited(controller.stopEmulator(entry.name)),
        );
      },
    );
  }

  /// The two ways an SDK can come up short need opposite advice: a missing SDK
  /// sends the user looking for one, while a missing `emulator` package sends
  /// them to the SDK they already have.
  Widget _buildSdkNotice(AndroidSdkLocation sdk) {
    return switch (sdk.status) {
      AndroidSdkStatus.emulatorMissing => CenteredStateMessage(
        icon: Icons.extension_off_outlined,
        title: 'The emulator package is not installed',
        description:
            'An Android SDK is at ${sdk.sdkPath}, but it has no emulator. '
            'Install it from Android Studio’s SDK Manager, under SDK Tools.',
      ),
      AndroidSdkStatus.sdkMissing => const CenteredStateMessage(
        icon: Icons.folder_off_outlined,
        title: 'No Android SDK found',
        description:
            'Eagly bundles adb, but the emulator ships with your own Android '
            'SDK — install one through Android Studio, or point Eagly at it '
            'in Settings.',
      ),
      AndroidSdkStatus.ready => const SizedBox.shrink(),
    };
  }
}
