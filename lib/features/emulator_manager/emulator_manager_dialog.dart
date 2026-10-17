import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/app_icon_button.dart';
import '../../data/device.dart';
import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/eagly_dialog.dart';
import '../../session/device_session_manager.dart';
import '../wireless_connection/components/wireless_feedback_banner.dart';
import 'components/create_emulator_sheet.dart';
import 'components/emulator_tile.dart';
import 'components/sdk_notice.dart';
import 'services/android_sdk_picker.dart';
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
class const EmulatorManagerDialog({
  super.key,
  required final DeviceSessionManager manager,
  required final ValueChanged<String> onShowSnackBar,

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
  createController,
}) extends StatefulWidget {
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

  Future<void> _handleTileAction(
    EmulatorEntry entry,
    EmulatorTileAction action,
  ) async {
    if (action == EmulatorTileAction.delete) {
      if (await _confirmDelete(entry.label)) {
        await controller.deleteEmulator(entry.name);
      }
      return;
    }

    if (action == EmulatorTileAction.wipeData &&
        !await _confirmWipe(entry.label)) {
      return;
    }
    if (!mounted) return;

    await controller.launch(
      entry.name,
      options: switch (action) {
        EmulatorTileAction.coldBoot => const EmulatorLaunchOptions(
          coldBoot: true,
        ),
        EmulatorTileAction.wipeData => const EmulatorLaunchOptions(
          wipeData: true,
        ),
        _ => EmulatorLaunchOptions.normal,
      },
    );
  }

  /// Opens the create sheet, loading its options in the background so the
  /// fields are usable before `avdmanager` has finished starting its JVM.
  Future<void> _handleCreate() async {
    unawaited(controller.loadCreationOptions());

    final request = await showDialog<CreateEmulatorRequest>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CreateEmulatorSheet(
          systemImages: controller.systemImages,
          deviceProfiles: controller.deviceProfiles,
          isLoading: controller.isLoadingCreationOptions,
          existingNames: {for (final entry in controller.entries) entry.name},
        ),
      ),
    );
    if (request == null || !mounted) return;

    await controller.createEmulator(
      name: request.name,
      packagePath: request.packagePath,
      deviceProfileId: request.deviceProfileId,
    );
  }

  Future<bool> _confirmDelete(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete this emulator?'),
        content: Text(
          '$label and everything on it is removed from disk. Recreating it '
          'is easy; getting its contents back is not.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
            if (controller.canManageAvds)
              TextButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () => unawaited(_handleCreate()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            AppIconButton(
              tooltip: 'Refresh',
              busy: controller.isLoading,
              onPressed: () => unawaited(controller.refresh()),
              icon: Icons.refresh_rounded,
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

    if (!sdk.isReady) {
      return SdkNotice(sdk: sdk, onLocate: () => unawaited(_locateSdk()));
    }

    if (controller.entries.isEmpty) {
      return CenteredStateMessage(
        icon: Icons.phone_android_outlined,
        title: 'No emulators yet',
        description: controller.canManageAvds
            ? 'Create one from a system image you already have installed.'
            : 'This SDK has no virtual devices, and no cmdline-tools to '
                  'create one with. Add them from Android Studio’s SDK '
                  'Manager, or create an emulator in its Device Manager.',
        footer: controller.canManageAvds
            ? FilledButton.tonalIcon(
                onPressed: () => unawaited(_handleCreate()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New emulator'),
              )
            : null,
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
          canDelete: controller.canManageAvds,
          onAction: (action) => unawaited(_handleTileAction(entry, action)),
          onStop: () => unawaited(controller.stopEmulator(entry.name)),
        );
      },
    );
  }

  /// Lets the user point Eagly at their SDK without a detour through
  /// Settings — this dialog is where they find out it is missing.
  Future<void> _locateSdk() async {
    final choice = await AndroidSdkPicker.chooseAndSave(
      initialDirectory: controller.sdk?.sdkPath,
    );
    if (choice == null || !mounted) return;

    widget.onShowSnackBar(choice.message);
    if (choice.accepted) await controller.refresh();
  }
}
