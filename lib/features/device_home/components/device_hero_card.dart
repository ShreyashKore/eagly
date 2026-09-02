import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/components/feature_view.dart';
import '../../../session/device_session_controller.dart';
import '../data/device_info.dart';
import '../device_home_controller.dart';
import 'home_primitives.dart';
import '../../../presentation/theme/app_theme.dart';

/// Top-of-screen identity banner: who the device is, whether it is ready to
/// work with, and the one action most sessions start with (install a build).
class DeviceHeroCard extends StatelessWidget {
  const DeviceHeroCard({
    super.key,
    required this.session,
    required this.homeController,
    required this.info,
  });

  final DeviceSessionController session;
  final DeviceHomeController homeController;
  final DeviceInfo info;

  Future<void> _install(BuildContext context) async {
    final result = await session.installAppFromPicker();
    if (!context.mounted || result.cancelled) return;
    final message = result.isSuccess
        ? result.message ?? 'Installed ${result.fileName}.'
        : result.error ?? 'Installation failed.';
    FeatureView.showSnackBar(context, message);
    if (result.isSuccess) unawaited(homeController.refreshRecentApps());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = session.device;
    final identity = info.identity;
    final isIos = device is IosDevice;
    final wireless = device is AndroidDevice && device.isWireless;

    final osLabel = identity.osVersion == null
        ? (isIos ? 'iOS' : 'Android')
        : '${identity.osName ?? (isIos ? 'iOS' : 'Android')} '
              '${identity.osVersion}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _PlatformBadge(device: device),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(
                        label: device.isConnected
                            ? 'Online'
                            : device.statusLabel,
                        tone: device.isConnected
                            ? StatusTone.good
                            : StatusTone.bad,
                        showDot: true,
                      ),
                      StatusPill(
                        label: osLabel,
                        icon: isIos ? Icons.apple : Icons.android,
                      ),
                      if (!isIos)
                        StatusPill(
                          label: wireless ? 'Wi-Fi' : 'USB',
                          icon: wireless ? Icons.wifi : Icons.usb,
                        ),
                      if (identity.cpuArchitecture != null)
                        StatusPill(
                          label: identity.cpuArchitecture!,
                          icon: Icons.memory,
                        ),
                      StatusPill(
                        label: device.id,
                        icon: Icons.tag,
                        mono: true,
                        trailing: CopyButton(
                          value: device.id,
                          label: isIos ? 'UDID' : 'device ID',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(16),
            _InstallAction(
              session: session,
              onInstall: () => _install(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIos = device is IosDevice;
    return Container(
      width: context.scaled(46),
      height: context.scaled(46),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(
        isIos ? Icons.phone_iphone : Icons.phone_android,
        size: 24,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _InstallAction extends StatelessWidget {
  const _InstallAction({required this.session, required this.onInstall});

  final DeviceSessionController session;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installing = session.isInstallingApp;
    final types = session.platform == DevicePlatform.android
        ? 'Drop an .apk anywhere'
        : 'Drop an .ipa anywhere';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: installing || !session.isConnected ? null : onInstall,
          icon: installing
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.system_update_outlined, size: 17),
          label: Text(
            installing
                ? 'Installing ${session.installingAppName ?? "app"}…'
                : 'Install App',
          ),
        ),
        const Gap(6),
        Text(
          types,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
