import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../presentation/components/app_icon_button.dart';
import '../../presentation/components/ios_support_notice.dart';
import '../../presentation/components/layout_constants.dart';
import '../../presentation/theme/platform_look.dart';
import '../../services/eagly_info_service.dart';
import '../../session/device_session_manager.dart';
import 'components/home_device_list.dart';
import 'components/home_start_list.dart';
import 'components/recent_files_list.dart';

/// Landing screen shown when no device tab is selected, laid out like a
/// desktop IDE's start page: the app's name and version on top, a Start
/// list (with shortcuts) and the recent log files on the left, and the
/// detected devices on the right. Narrow windows stack the two columns.
class const HomeView({
  super.key,
  required final DeviceSessionManager manager,
  required final VoidCallback onShowWireless,
  required final VoidCallback onShowEmulators,
  required final ValueChanged<String> onShowMessage,

  /// Opens a log file via the system picker (no device required).
  required final VoidCallback onImportLog,

  /// Re-opens a previously imported log file by its absolute [path].
  required final ValueChanged<String> onOpenRecent,
}) extends StatelessWidget {
  /// Below this content width the Start column stacks above the devices.
  static const double twoColumnMinWidth = 640;

  /// Width of the Start column in the two-column layout.
  static const double startColumnWidth = 272;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = [
      HomeStartAction(
        icon: Icons.wifi_tethering_outlined,
        label: 'Wireless pairing',
        key: LogicalKeyboardKey.keyP,
        onPressed: onShowWireless,
      ),
      HomeStartAction(
        icon: Icons.smartphone_outlined,
        label: 'Emulators',
        key: LogicalKeyboardKey.keyE,
        onPressed: onShowEmulators,
      ),
      HomeStartAction(
        icon: Icons.folder_open_outlined,
        label: 'Open log file',
        key: LogicalKeyboardKey.keyO,
        onPressed: onImportLog,
      ),
    ];

    return HomeStartShortcuts(
      actions: actions,
      child: ColoredBox(
        // The gap colour between panes, so the panel reads as one more pane.
        color: theme.colorScheme.surfaceContainerLowest,
        child: Align(
          alignment: const Alignment(0, -0.3),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LayoutConstants.getStartedMaxWidth,
              ),
              child: _Panel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 22, 24, 20),
                      child: _Masthead(),
                    ),
                    const Divider(height: 1),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final start = Padding(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              HomeStartList(actions: actions),
                              const SizedBox(height: 20),
                              RecentFilesList(onOpenRecent: onOpenRecent),
                            ],
                          ),
                        );
                        final devices = Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 14, 18),
                          child: _DevicesSection(
                            manager: manager,
                            onShowMessage: onShowMessage,
                          ),
                        );
                        if (constraints.maxWidth < twoColumnMinWidth) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              start,
                              const Divider(height: 1),
                              devices,
                            ],
                          );
                        }
                        // The rule between the columns runs the height of
                        // the taller one, without measuring either.
                        return Stack(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: startColumnWidth, child: start),
                                const SizedBox(width: 1),
                                Expanded(child: devices),
                              ],
                            ),
                            const Positioned(
                              left: startColumnWidth,
                              top: 0,
                              bottom: 0,
                              child: VerticalDivider(width: 1),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised, bordered surface that holds the whole start page, so it sits
/// in the window like a pane rather than floating loose in it.
class const _Panel({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(PlatformLook.surfaceRadius + 4);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// The app icon, its name with the running version beside it, and what it
/// is for.
class const _Masthead() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = EaglyInfoService.appVersion;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(LocalAssets.appIcon, height: 52, width: 52),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (version != 'Unknown') ...[
                    const SizedBox(width: 10),
                    _VersionPill(version: version),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Stream live device logs, or open a saved log file.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class const _VersionPill({required final String version})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'v$version',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colorScheme.primary),
      ),
    );
  }
}

/// The detected devices, under a header with their count and a refresh
/// button. Flat: the [_Panel] around the page is its surface.
class const _DevicesSection({
  required final DeviceSessionManager manager,
  required final ValueChanged<String> onShowMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final count = manager.sessions
            .where((session) => !session.isImportedWorkspace)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              // The Start label's line, so both columns' headings align.
              height: 20,
              child: Row(
                children: [
                  Text(
                    count > 0 ? 'Devices  ·  $count found' : 'Devices',
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                  const Spacer(),
                  // A 20-high slot the button overhangs, so it doesn't push
                  // the heading lower than the Start column's.
                  SizedBox(
                    width: 28,
                    child: OverflowBox(
                      maxWidth: 40,
                      maxHeight: 40,
                      child: AppIconButton(
                        tooltip: 'Load devices',
                        icon: Icons.refresh_rounded,
                        iconSize: 16,
                        onPressed: manager.isLoadingDevices
                            ? null
                            : manager.refreshDevices,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            HomeDeviceList(manager: manager, onShowMessage: onShowMessage),
            if (Platform.isWindows && manager.iosSupportUnavailable)
              IosSupportNotice(devices: manager.unreachableIosDevices),
          ],
        );
      },
    );
  }
}
