import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../data/device.dart';
import '../../session/device_session_controller.dart';
import '../../utils/utils.dart';
import 'device_home_controller.dart';

class DeviceHomeFeatureView extends StatelessWidget {
  const DeviceHomeFeatureView({
    super.key,
    required this.session,
    required this.homeController,
    required this.onShowSnackBar,
  });

  final DeviceSessionController session;
  final DeviceHomeController homeController;
  final void Function(String) onShowSnackBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!session.isConnected) {
      return _DisconnectedView(device: session.device, theme: theme);
    }

    return ListenableBuilder(
      listenable: homeController,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child:  _DeviceInfoCard(
                      session: session,
                      onShowSnackBar: onShowSnackBar,
                    ),
                  ),
                  const Gap(20),
                  _AppInstallCard(
                    session: session,
                    homeController: homeController,
                    onShowSnackBar: onShowSnackBar,
                  ),
                ],
              ),
              const Gap(20),
              _PerformanceSection(homeController: homeController),
              const Gap(20),
              _FeatureShortcuts(session: session),
            ],
          ),
        );
      },
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView({required this.device, required this.theme});

  final Device device;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.usb_off_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const Gap(16),
          Text(
            'Device Disconnected',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(4),
          Text(
            device.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceInfoCard extends StatefulWidget {
  const _DeviceInfoCard({
    required this.session,
    required this.onShowSnackBar,
  });

  final DeviceSessionController session;
  final void Function(String) onShowSnackBar;

  @override
  State<_DeviceInfoCard> createState() => _DeviceInfoCardState();
}

class _DeviceInfoCardState extends State<_DeviceInfoCard> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = widget.session.device;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildPlatformIcon(device, theme),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(2),
                      Row(
                        children: [
                          _StatusDot(device: device),
                          const Gap(6),
                          Text(
                            device.statusLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (device is AndroidDevice && device.isWireless)
                            ...[
                              const Gap(6),
                              Icon(
                                Icons.wifi,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ],
                          if (device is AndroidDevice && !device.isWireless)
                            ...[
                              const Gap(6),
                              Icon(
                                Icons.usb,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(16),
            const Divider(),
            const Gap(16),
            _InfoRow(
              label: 'Platform',
              value: device.platform == DevicePlatform.android
                  ? 'Android'
                  : 'iOS',
            ),
            if (device.brand != null && device.brand!.isNotEmpty)
              _InfoRow(label: 'Brand', value: device.brand!),
            if (device.model != null && device.model!.isNotEmpty)
              _InfoRow(label: 'Model', value: device.model!),
            if (device.name != null && device.name!.isNotEmpty)
              _InfoRow(label: 'Code Name', value: device.name!),
            if (device is AndroidDevice && device.serialNumber != null)
              _InfoRow(label: 'Serial', value: device.serialNumber!),
            _buildIdRow(device, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildIdRow(Device device, ThemeData theme) {
    final id = device.id;
    final idLabel = device is IosDevice ? 'UDID' : 'Device ID';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              idLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Gap(8),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SelectableText(
                id,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const Gap(4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Clipboard.setData(ClipboardData(text: id));
              widget.onShowSnackBar('Copied $idLabel to clipboard.');
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformIcon(Device device, ThemeData theme) {
    final icon = device is IosDevice ? Icons.phone_iphone : Icons.phone_android;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 24, color: theme.colorScheme.onPrimaryContainer),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final color = device.isConnected
        ? const Color(0xFF4ADE80)
        : Theme.of(context).colorScheme.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Gap(8),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.homeController});

  final DeviceHomeController homeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = homeController.stats;

    if (homeController.isLoading && stats.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Performance',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(12),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Performance',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (homeController.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
            const Gap(16),
            if (stats.cpu != null) ...[
              _ProgressBar(
                label: 'CPU',
                detail:
                    '${stats.cpu!.utilisationPercent.toStringAsFixed(1)}%  '
                    '(${stats.cpu!.coreCount} core${stats.cpu!.coreCount == 1 ? '' : 's'}, '
                    'load ${stats.cpu!.loadAverage1m.toStringAsFixed(2)})',
                value: stats.cpu!.utilisationPercent / 100,
                foreground: _cpuColor(stats.cpu!.utilisationPercent),
              ),
              const Gap(12),
            ],
            if (stats.memory != null)
              _ProgressBar(
                label: 'Memory',
                detail:
                    '${formatBytes(stats.memory!.usedKb * 1024)} / '
                    '${formatBytes(stats.memory!.totalKb * 1024)}',
                value: stats.memory!.usagePercent / 100,
                foreground: _memColor(stats.memory!.usagePercent),
              ),
          ],
        ),
      ),
    );
  }

  Color _cpuColor(double pct) {
    if (pct > 80) return Colors.redAccent;
    if (pct > 50) return Colors.orangeAccent;
    return const Color(0xFF4ADE80);
  }

  Color _memColor(double pct) {
    if (pct > 85) return Colors.redAccent;
    if (pct > 60) return Colors.orangeAccent;
    return const Color(0xFF4ADE80);
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.label,
    required this.detail,
    required this.value,
    required this.foreground,
  });

  final String label;
  final String detail;
  final double value;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const Gap(6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: foreground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppInstallCard extends StatelessWidget {
  const _AppInstallCard({
    required this.session,
    required this.homeController,
    required this.onShowSnackBar,
  });

  final DeviceSessionController session;
  final DeviceHomeController homeController;
  final void Function(String) onShowSnackBar;

  Future<void> _handleInstall(BuildContext context) async {
    final result = await session.installAppFromPicker();
    if (!context.mounted || result.cancelled) return;
    final message = result.isSuccess
        ? result.message ?? 'Installed ${result.fileName}.'
        : result.error ?? 'Installation failed.';
    onShowSnackBar(message);
    if (result.isSuccess) {
      unawaited(homeController.refreshRecentApps());
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = homeController.recentApps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Install',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(12),
            Column(
              children: [
                FilledButton.icon(
                  onPressed:
                      session.isInstallingApp || !session.isConnected
                          ? null
                          : () => _handleInstall(context),
                  icon: session.isInstallingApp
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.system_update_outlined, size: 18),
                  label: Text(
                    session.isInstallingApp
                        ? 'Installing ${session.installingAppName ?? "app"}…'
                        : 'Install App',
                  ),
                ),
                const Gap(12),
                Text(
                  session.platform == DevicePlatform.android
                      ? 'APK files'
                      : 'IPA / .app files',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (homeController.isLoadingRecentApps) ...[
              const Gap(16),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ] else if (recent.isNotEmpty) ...[
              const Gap(16),
              const Divider(),
              const Gap(12),
              Text(
                'Recently Installed',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(8),
              ...recent.map(
                (install) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: const Color(0xFF4ADE80),
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          install.displayName,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (install.installTime != null) ...[
                        const Gap(8),
                        Text(
                          _formatTime(install.installTime!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureShortcuts extends StatefulWidget {
  const _FeatureShortcuts({required this.session});

  final DeviceSessionController session;

  @override
  State<_FeatureShortcuts> createState() => _FeatureShortcutsState();
}

class _FeatureShortcutsState extends State<_FeatureShortcuts> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Access',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ShortcutCard(
              icon: Icons.article_outlined,
              label: 'Logs',
              sublabel: 'View device logs',
              isActive: s.isLogsOpen,
              onTap: s.toggleLogs,
            ),
            if (s.canMirror)
              _ShortcutCard(
                icon: Icons.mobile_screen_share,
                label: 'Mirror',
                sublabel: 'Screen mirror',
                isActive: s.isMirrorOpen,
                onTap: s.toggleMirror,
              ),
            if (s.canReadCrashReports)
              _ShortcutCard(
                icon: Icons.bug_report_outlined,
                label: 'Crash Reports',
                sublabel: 'View crash logs',
                isActive: s.isCrashReportsOpen,
                onTap: s.toggleCrashReports,
              ),
            if (s.canManageFiles)
              _ShortcutCard(
                icon: Icons.folder_outlined,
                label: 'File Manager',
                sublabel: 'Browse device files',
                isActive: s.isFilesOpen,
                onTap: s.toggleFiles,
              ),
          ],
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 180,
      child: Material(
        color:
            isActive
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color:
                      isActive
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                ),
                const Gap(8),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(2),
                Text(
                  sublabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
