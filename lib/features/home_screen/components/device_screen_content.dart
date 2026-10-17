import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
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
import 'pane_resize_handle.dart';

/// The content area of the device screen: guidance when the device needs user
/// action, otherwise Home or the feature workspace (Logs always; Mirror,
/// Crash Reports, Files, Apps, Utilities and Terminal alongside when open).
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
    final logController = session.logSessionManager.selectedTab;
    final mirror = session.mirrorController;
    final crashReports = session.crashReportController;
    final files = session.fileManagerController;
    final apps = session.appsController;
    final utilities = session.utilitiesController;
    final terminal = session.terminalSessionManager;

    // Open features split the full width proportionally to their pane widths,
    // so no empty space remains; the dividers still resize them by ratio.
    return ListenableBuilder(
      listenable: Listenable.merge([
        logController,
        mirror,
        crashReports,
        files,
        apps,
        utilities,
        terminal,
      ]),
      builder: (context, _) => Row(
        children: [
          if (session.isLogsOpen && logController != null) ...[
            Expanded(
              flex: logController.paneWidth.round(),
              child: LogFeatureView(
                logManager: session.logSessionManager,
                session: session,
                appMemoryBytesListenable: appMemoryBytesListenable,
                onClose: session.closeLogs,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => logController.paneWidth,
              onResize: logController.setPaneWidth,
            ),
          ],
          if (session.isMirrorOpen) ...[
            Expanded(
              flex: mirror.paneWidth.round(),
              child: MirrorFeatureView(
                controller: mirror,
                onClose: session.closeMirror,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => mirror.paneWidth,
              onResize: mirror.setPaneWidth,
            ),
          ],
          if (session.isCrashReportsOpen) ...[
            Expanded(
              flex: crashReports.paneWidth.round(),
              child: CrashReportFeatureView(
                controller: crashReports,
                onClose: session.closeCrashReports,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => crashReports.paneWidth,
              onResize: crashReports.setPaneWidth,
            ),
          ],
          if (session.isFilesOpen) ...[
            Expanded(
              flex: files.paneWidth.round(),
              child: FileManagerFeatureView(
                controller: files,
                onClose: session.closeFiles,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => files.paneWidth,
              onResize: files.setPaneWidth,
            ),
          ],
          if (session.isAppsOpen) ...[
            Expanded(
              flex: apps.paneWidth.round(),
              child: AppsFeatureView(
                controller: apps,
                onClose: session.closeApps,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => apps.paneWidth,
              onResize: apps.setPaneWidth,
            ),
          ],
          if (session.isUtilitiesOpen) ...[
            Expanded(
              flex: utilities.paneWidth.round(),
              child: UtilitiesFeatureView(
                controller: utilities,
                onClose: session.closeUtilities,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => utilities.paneWidth,
              onResize: utilities.setPaneWidth,
            ),
          ],
          if (session.isTerminalOpen) ...[
            Expanded(
              flex: terminal.paneWidth.round(),
              child: TerminalFeatureView(
                manager: terminal,
                onClose: session.closeTerminal,
              ),
            ),
            PaneResizeHandle(
              paneWidth: () => terminal.paneWidth,
              onResize: terminal.setPaneWidth,
            ),
          ],
        ],
      ),
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
        message:
            'Your iPhone is locked. Unlock it and trust this computer to continue.',
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
