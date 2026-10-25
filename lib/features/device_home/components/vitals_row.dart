import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/device_info.dart';
import '../data/device_performance_stats.dart';
import 'home_primitives.dart';

/// The four live vitals — battery, storage, CPU, memory — as gauges. This is
/// the top-priority block: everything here is a number that changes while you
/// work, so it is shown graphically rather than as label/value text.
class const VitalsRow({
  super.key,
  required final DeviceBatteryInfo battery,
  required final DeviceStorageInfo storage,
  required final DevicePerformanceStats stats,
  required final List<double> cpuHistory,
  required final List<double> memoryHistory,

  /// Renders the last known values in a muted palette with a "last seen" tag,
  /// so a frozen reading never looks live.
  final bool isStale = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (!battery.isEmpty) _BatteryTile(battery: battery, stale: isStale),
      if (!storage.isEmpty) _StorageTile(storage: storage, stale: isStale),
      if (stats.cpu != null)
        _CpuTile(cpu: stats.cpu!, history: cpuHistory, stale: isStale),
      if (stats.memory != null)
        _MemoryTile(
          memory: stats.memory!,
          history: memoryHistory,
          stale: isStale,
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = math.min(
          tiles.length,
          math.max(1, (constraints.maxWidth + spacing) ~/ (232 + spacing)),
        );
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns - 0.01;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// Common shell for a vitals tile: gauge on the left, headline + detail on
/// the right, optional sparkline strip underneath.
class const _VitalTile({
  required final String label,
  required final double? value,
  required final String headline,
  required final String detail,
  required final Color color,
  required final IconData centerIcon,
  final bool stale = false,
  final List<double>? history,
  final Widget? badge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = this.history;
    final color = stale
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
        : this.color;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                MetricGauge(
                  value: value,
                  color: color,
                  size: 58,
                  stroke: 5,
                  center: Icon(centerIcon, size: 17, color: color),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.7,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (stale)
                            Text(
                              'LAST SEEN',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.8),
                              ),
                            )
                          else if (badge != null)
                            badge!,
                        ],
                      ),
                      const Gap(2),
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.3,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (history != null && history.length > 1) ...[
              const Gap(8),
              Sparkline(samples: history, color: color, height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class const _BatteryTile({
  required final DeviceBatteryInfo battery,
  required final bool stale,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.eaglyTheme;
    final percentage = battery.percentage;
    final charging = battery.chargingState == BatteryChargingState.charging;
    final color = switch (percentage) {
      null => tokens.statusLiveColor,
      final p when p <= 15 => tokens.errorColor,
      final p when p <= 30 => tokens.warningColor,
      _ => tokens.statusLiveColor,
    };

    final detail = [
      if (battery.chargingState != null) _chargingLabel(battery.chargingState!),
      if (battery.health != null) _healthLabel(battery.health!),
      if (battery.temperatureCelsius != null)
        '${battery.temperatureCelsius!.toStringAsFixed(1)}°C',
    ].join(' · ');

    return _VitalTile(
      label: 'Battery',
      value: percentage == null ? null : percentage / 100,
      headline: percentage == null ? '—' : '$percentage%',
      detail: detail.isEmpty ? 'Level unavailable' : detail,
      color: color,
      stale: stale,
      centerIcon: charging ? Icons.bolt_rounded : Icons.battery_std_outlined,
      badge: charging
          ? Icon(Icons.power_rounded, size: 13, color: color)
          : null,
    );
  }

  String _chargingLabel(BatteryChargingState state) => switch (state) {
    BatteryChargingState.charging => 'Charging',
    BatteryChargingState.discharging => 'On battery',
    BatteryChargingState.full => 'Full',
    BatteryChargingState.notCharging => 'Not charging',
  };

  String _healthLabel(BatteryHealth health) => switch (health) {
    BatteryHealth.good => 'Good',
    BatteryHealth.overheat => 'Overheating',
    BatteryHealth.dead => 'Dead',
    BatteryHealth.overVoltage => 'Over voltage',
    BatteryHealth.cold => 'Cold',
  };
}

class const _StorageTile({
  required final DeviceStorageInfo storage,
  required final bool stale,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final percent = storage.usagePercent;
    final total = storage.totalBytes;
    final free = storage.availableBytes;

    final detail = total == null
        ? 'Capacity unknown'
        : '${formatBytes(storage.usedBytes ?? 0)} used of '
              '${formatBytes(total)}'
              '${free == null ? '' : ' · ${formatBytes(free)} free'}';

    return _VitalTile(
      label: 'Storage',
      value: percent == null ? null : percent / 100,
      headline: percent == null ? '—' : '${percent.toStringAsFixed(0)}%',
      detail: detail,
      color: usageColor(context, percent ?? 0),
      stale: stale,
      centerIcon: Icons.sd_storage_outlined,
    );
  }
}

class const _CpuTile({
  required final CpuStats cpu,
  required final List<double> history,
  required final bool stale,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final percent = cpu.utilisationPercent;
    return _VitalTile(
      label: 'CPU',
      value: percent / 100,
      headline: '${percent.toStringAsFixed(0)}%',
      detail:
          '${pluralize(cpu.coreCount, 'core')} · load '
          '${cpu.loadAverage1m.toStringAsFixed(2)} / '
          '${cpu.loadAverage5m.toStringAsFixed(2)} / '
          '${cpu.loadAverage15m.toStringAsFixed(2)}',
      color: usageColor(context, percent, warn: 50, bad: 80),
      stale: stale,
      centerIcon: Icons.developer_board,
      history: history,
    );
  }
}

class const _MemoryTile({
  required final MemoryStats memory,
  required final List<double> history,
  required final bool stale,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final percent = memory.usagePercent;
    return _VitalTile(
      label: 'Memory',
      value: percent / 100,
      headline: '${percent.toStringAsFixed(0)}%',
      detail:
          '${formatBytes(memory.usedKb * 1024)} of '
          '${formatBytes(memory.totalKb * 1024)} · '
          '${formatBytes(memory.availableKb * 1024)} available',
      color: usageColor(context, percent, warn: 60, bad: 85),
      stale: stale,
      centerIcon: Icons.memory_rounded,
      history: history,
    );
  }
}
