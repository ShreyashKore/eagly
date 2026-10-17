import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../../session/workspace_layout.dart';
import '../../apps/apps_feature_view.dart';
import '../../crash_reports/crash_report_feature_view.dart';
import '../../device_home/device_home_feature_view.dart';
import '../../file_manager/file_manager_feature_view.dart';
import '../../logs/log_feature_view.dart';
import '../../mirror/mirror_feature_view.dart';
import '../../terminal/terminal_feature_view.dart';
import '../../utilities/utilities_feature_view.dart';
import 'android_unauthorized_guidance.dart';
import 'ios_guidance.dart';
import 'workspace_view.dart';

/// The content area of the device screen: guidance when the device needs user
/// action, otherwise Home or the feature workspace — whichever of Logs,
/// Mirror, Crash Reports, Files, Apps, Utilities and Terminal are open, in
/// the arrangement the user gave them.
class DeviceScreenContent extends StatelessWidget {
  const DeviceScreenContent({
    super.key,
    required this.session,
    required this.appMemoryBytesListenable,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  Widget build(BuildContext context) {
    final guidance = _guidanceForDevice(session.device);
    if (guidance != null) {
      return guidance;
    }

    // Home and the feature workspace are mutually-exclusive views, but both
    // stay mounted (via Visibility, not a conditional build) so neither one's
    // widget-level state (scroll position, in-progress input, …) is lost when
    // the user switches away and back.
    return Stack(
      children: [
        Positioned.fill(
          child: Visibility(
            visible: !session.isHomeOpen,
            maintainState: true,
            maintainAnimation: true,
            child: _Workspace(
              session: session,
              appMemoryBytesListenable: appMemoryBytesListenable,
            ),
          ),
        ),
        Positioned.fill(
          child: Visibility(
            visible: session.isHomeOpen,
            maintainState: true,
            maintainAnimation: true,
            child: DeviceHomeFeatureView(
              session: session,
              homeController: session.homeController,
            ),
          ),
        ),
      ],
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.session,
    required this.appMemoryBytesListenable,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  Widget build(BuildContext context) {
    // Open panes are laid out however the user arranged them: side by side
    // by default, split, stacked or grouped into tabs by dragging a pane's
    // header (see docs/WORKSPACE_LAYOUT.md).
    return WorkspaceView(
      layout: session.workspaceLayout,
      paneBuilder: (context, pane) => switch (pane) {
        WorkspacePane.logs => LogFeatureView(
          logManager: session.logSessionManager,
          session: session,
          appMemoryBytesListenable: appMemoryBytesListenable,
          onClose: session.closeLogs,
        ),
        WorkspacePane.mirror => MirrorFeatureView(
          controller: session.mirrorController,
          onClose: session.closeMirror,
        ),
        WorkspacePane.crashReports => CrashReportFeatureView(
          controller: session.crashReportController,
          onClose: session.closeCrashReports,
        ),
        WorkspacePane.files => FileManagerFeatureView(
          controller: session.fileManagerController,
          onClose: session.closeFiles,
        ),
        WorkspacePane.apps => AppsFeatureView(
          controller: session.appsController,
          onClose: session.closeApps,
        ),
        WorkspacePane.utilities => UtilitiesFeatureView(
          controller: session.utilitiesController,
          onClose: session.closeUtilities,
        ),
        WorkspacePane.terminal => TerminalFeatureView(
          manager: session.terminalSessionManager,
          onClose: session.closeTerminal,
        ),
      },
    );
  }
}

/// Returns a guidance widget when [device] needs user action before it can be
/// used, or null if the device is ready.
Widget? _guidanceForDevice(Device device) {
  if (device is AndroidDevice) {
    if (device.status == 'unauthorized') {
      return const AndroidUnauthorizedGuidance();
    }
  } else if (device is IosDevice) {
    return switch (device.status) {
      'unpaired' => const IosGuidance(
        icon: Icons.phonelink_lock_outlined,
        title: 'Trust This Computer',
        message:
            'Your iPhone is asking whether to trust this Mac.\n'
            'Pick up your device and tap "Trust" on the dialog that appeared.',
        steps: [
          'Unlock your iPhone',
          'Tap "Trust" on the "Trust This Computer?" alert',
          'Enter your iPhone passcode if prompted',
        ],
      ),
      'locked' => const IosGuidance(
        icon: Icons.lock_outline,
        title: 'iPhone Locked',
        message: 'Your iPhone is locked. Unlock it and trust this computer to continue.',
        steps: [
          'Unlock your iPhone with Face ID, Touch ID, or passcode',
          'If prompted, tap "Trust" on the "Trust This Computer?" alert',
        ],
      ),
      'unavailable' => const IosGuidance(
        icon: Icons.usb_off_outlined,
        title: 'Device Unavailable',
        message: 'Could not communicate with your iPhone. Try the steps below.',
        steps: [
          'Unlock your iPhone',
          'Disconnect and reconnect the USB cable',
          'If prompted, tap "Trust This Computer"',
        ],
      ),
      _ => null,
    };
  }
  return null;
}
