import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/device_info.dart';
import '../data/installed_app_info.dart';
import 'home_primitives.dart';

/// Secondary, slower-moving device facts. Each card groups one topic so the
/// grid stays scannable instead of one long list of label/value rows.

// ── Debug readiness ──────────────────────────────────────────────────────

class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    super.key,
    required this.device,
    required this.developerState,
  });

  final Device device;
  final DeviceDeveloperStateInfo developerState;

  @override
  Widget build(BuildContext context) {
    final isIos = device is IosDevice;
    final pills = <Widget>[
      if (developerState.debuggingReady != null)
        _readinessPill(
          context,
          label: isIos ? 'Debugging' : 'ADB bridge',
          ok: developerState.debuggingReady!,
          okText: 'Ready',
          badText: 'Not ready',
        ),
      if (developerState.pairingState != null)
        _readinessPill(
          context,
          label: 'Pairing',
          ok: developerState.pairingState == 'Paired',
          okText: developerState.pairingState!,
          badText: developerState.pairingState!,
        ),
      if (developerState.developerModeEnabled != null)
        _readinessPill(
          context,
          label: 'Developer mode',
          ok: developerState.developerModeEnabled!,
          okText: 'On',
          badText: 'Off',
        ),
      if (developerState.adbEnabled != null)
        _readinessPill(
          context,
          label: 'USB debugging',
          ok: developerState.adbEnabled!,
          okText: 'On',
          badText: 'Off',
        ),
    ];

    return SectionCard(
      title: 'Debug readiness',
      icon: Icons.verified_user_outlined,
      child: Wrap(spacing: 8, runSpacing: 8, children: pills),
    );
  }

  Widget _readinessPill(
    BuildContext context, {
    required String label,
    required bool ok,
    required String okText,
    required String badText,
  }) {
    return StatusPill(
      label: '$label · ${ok ? okText : badText}',
      tone: ok ? StatusTone.good : StatusTone.warn,
      icon: ok ? Icons.check_circle_outline : Icons.error_outline,
    );
  }
}

// ── Hardware ─────────────────────────────────────────────────────────────

class HardwareCard extends StatelessWidget {
  const HardwareCard({super.key, required this.device, required this.identity});

  final Device device;
  final DeviceIdentityInfo identity;

  @override
  Widget build(BuildContext context) {
    final device = this.device;
    final isIos = device is IosDevice;
    final items = <SpecItem>[
      if (identity.manufacturer != null)
        SpecItem('Manufacturer', identity.manufacturer!),
      if (device.brand != null && device.brand!.isNotEmpty)
        SpecItem('Brand', device.brand!),
      if (device.model != null && device.model!.isNotEmpty)
        SpecItem('Model', device.model!),
      if (device.name != null && device.name!.isNotEmpty)
        SpecItem('Code name', device.name!),
      if (identity.buildVersion != null)
        SpecItem('Build', identity.buildVersion!, mono: true),
      if (identity.cpuArchitecture != null)
        SpecItem('CPU', identity.cpuArchitecture!),
      if (device is AndroidDevice && device.serialNumber != null)
        SpecItem('Serial', device.serialNumber!, copyable: true),
      SpecItem(isIos ? 'UDID' : 'Device ID', device.id, copyable: true),
    ];

    return SectionCard(
      title: 'Hardware',
      icon: Icons.developer_board_outlined,
      child: SpecGrid(items: items),
    );
  }
}

// ── Display ──────────────────────────────────────────────────────────────

class DisplayCard extends StatelessWidget {
  const DisplayCard({super.key, required this.display});

  final DeviceDisplayInfo display;

  @override
  Widget build(BuildContext context) {
    final width = display.widthPx;
    final height = display.heightPx;
    final landscape = display.orientation == DisplayOrientation.landscape;

    final items = <SpecItem>[
      if (width != null && height != null)
        SpecItem('Resolution', '$width × $height'),
      if (display.densityDpi != null)
        SpecItem('Density', '${display.densityDpi} dpi'),
      if (display.refreshRateHz != null)
        SpecItem('Refresh', '${display.refreshRateHz!.toStringAsFixed(0)} Hz'),
      if (display.orientation != null)
        SpecItem('Orientation', landscape ? 'Landscape' : 'Portrait'),
    ];

    return SectionCard(
      title: 'Display',
      icon: Icons.smartphone_outlined,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ScreenGlyph(widthPx: width, heightPx: height, landscape: landscape),
          const Gap(14),
          Expanded(child: SpecGrid(items: items, minColumnWidth: 110)),
        ],
      ),
    );
  }
}

/// A to-scale outline of the device screen — communicates aspect ratio and
/// orientation instantly, which "1080 × 2400" alone does not.
class _ScreenGlyph extends StatelessWidget {
  const _ScreenGlyph({
    required this.widthPx,
    required this.heightPx,
    required this.landscape,
  });

  final int? widthPx;
  final int? heightPx;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const boxHeight = 74.0;
    var ratio = widthPx != null && heightPx != null && heightPx! > 0
        ? widthPx! / heightPx!
        : 0.46;
    if (landscape && ratio < 1) ratio = 1 / ratio;
    final glyphHeight = landscape ? boxHeight * 0.62 : boxHeight;
    final glyphWidth = (glyphHeight * ratio).clamp(24.0, 120.0);

    return SizedBox(
      height: boxHeight,
      width: glyphWidth,
      child: Center(
        child: Container(
          width: glyphWidth,
          height: glyphHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outline, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.22),
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: glyphWidth * 0.28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Connectivity ─────────────────────────────────────────────────────────

class ConnectivityCard extends StatelessWidget {
  const ConnectivityCard({
    super.key,
    required this.connectivity,
    required this.cellular,
  });

  final DeviceConnectivityInfo connectivity;
  final DeviceCellularInfo cellular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggles = <Widget>[
      if (connectivity.usbConnected != null)
        ToggleTile(
          icon: connectivity.usbConnected! ? Icons.usb : Icons.wifi_tethering,
          label: connectivity.usbConnected! ? 'USB' : 'Wireless',
          enabled: true,
        ),
      if (connectivity.wifiEnabled != null)
        ToggleTile(
          icon: connectivity.wifiEnabled! ? Icons.wifi : Icons.wifi_off,
          label: 'Wi-Fi',
          enabled: connectivity.wifiEnabled!,
        ),
      if (connectivity.bluetoothEnabled != null)
        ToggleTile(
          icon: connectivity.bluetoothEnabled!
              ? Icons.bluetooth
              : Icons.bluetooth_disabled,
          label: 'Bluetooth',
          enabled: connectivity.bluetoothEnabled!,
        ),
    ];

    final cellularPills = <Widget>[
      if (cellular.carrierName != null)
        StatusPill(label: cellular.carrierName!, icon: Icons.cell_tower),
      if (cellular.networkType != null)
        StatusPill(label: cellular.networkType!, icon: Icons.network_cell),
      if (cellular.simState != null)
        StatusPill(label: 'SIM ${cellular.simState!}', icon: Icons.sim_card),
      if (cellular.simOperatorName != null &&
          cellular.simOperatorName != cellular.carrierName)
        StatusPill(label: cellular.simOperatorName!, icon: Icons.store),
      if (cellular.mcc != null && cellular.mnc != null)
        StatusPill(
          label: '${cellular.mcc}/${cellular.mnc}',
          icon: Icons.tag,
          mono: true,
        ),
    ];

    return SectionCard(
      title: 'Connectivity',
      icon: Icons.settings_ethernet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (toggles.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: toggles),
          if (connectivity.ipAddress != null) ...[
            const Gap(10),
            SpecGrid(
              items: [
                SpecItem('IP address', connectivity.ipAddress!, copyable: true),
              ],
            ),
          ],
          if (cellularPills.isNotEmpty) ...[
            const Gap(12),
            Text(
              'CELLULAR',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Gap(6),
            Wrap(spacing: 6, runSpacing: 6, children: cellularPills),
          ],
        ],
      ),
    );
  }
}

// ── Software ─────────────────────────────────────────────────────────────

class SoftwareCard extends StatelessWidget {
  const SoftwareCard({
    super.key,
    required this.software,
    required this.identity,
  });

  final DeviceSoftwareInfo software;
  final DeviceIdentityInfo identity;

  @override
  Widget build(BuildContext context) {
    final items = <SpecItem>[
      if (identity.osVersion != null)
        SpecItem(identity.osName ?? 'OS version', identity.osVersion!),
      if (software.sdkLevel != null)
        SpecItem('SDK level', 'API ${software.sdkLevel}'),
      if (software.securityPatch != null)
        SpecItem('Security patch', software.securityPatch!),
      if (software.locale != null) SpecItem('Locale', software.locale!),
      if (software.timeZone != null) SpecItem('Time zone', software.timeZone!),
    ];

    return SectionCard(
      title: 'Software & region',
      icon: Icons.shield_moon_outlined,
      child: SpecGrid(items: items),
    );
  }
}

// ── Recent installs ──────────────────────────────────────────────────────

class RecentInstallsCard extends StatelessWidget {
  const RecentInstallsCard({
    super.key,
    required this.apps,
    required this.isLoading,
  });

  final List<InstalledAppInfo> apps;
  final bool isLoading;

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Recently installed',
      icon: Icons.history_rounded,
      trailing: isLoading
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final app in apps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: context.eaglyTheme.statusLiveColor,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      app.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (app.installTime != null)
                    Text(
                      _formatTime(app.installTime!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
