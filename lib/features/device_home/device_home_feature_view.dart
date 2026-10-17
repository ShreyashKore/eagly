import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/feature_view.dart';
import '../../session/device_session_controller.dart';
import 'components/command_palette_hint.dart';
import 'components/detail_cards.dart';
import 'components/device_hero_card.dart';
import 'components/disconnected_state.dart';
import 'components/quick_access_bar.dart';
import 'components/vitals_row.dart';
import 'device_home_controller.dart';

/// The device dashboard — the first screen a connected device shows.
///
/// Layout priority, top to bottom: who the device is and the primary action
/// (install), the feature launcher, live vitals as gauges, then the slower
/// reference facts in a responsive card grid.
class const DeviceHomeFeatureView({
  super.key,
  required this.session,
  required this.homeController,
}) extends FeatureView {
  final DeviceSessionController session;
  final DeviceHomeController homeController;

  @override
  State<DeviceHomeFeatureView> createState() => _DeviceHomeFeatureViewState();
}

class _DeviceHomeFeatureViewState
    extends FeatureViewState<DeviceHomeFeatureView> {
  /// How many CPU/memory samples the sparklines keep.
  static const _historyLength = 40;

  final List<double> _cpuHistory = [];
  final List<double> _memoryHistory = [];
  Object? _lastStatsSample;

  @override
  Listenable get listenable => widget.homeController;

  @override
  void initState() {
    super.initState();
    widget.homeController.addListener(_recordSample);
  }

  @override
  void didUpdateWidget(DeviceHomeFeatureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeController != widget.homeController) {
      oldWidget.homeController.removeListener(_recordSample);
      widget.homeController.addListener(_recordSample);
      _cpuHistory.clear();
      _memoryHistory.clear();
      _lastStatsSample = null;
    }
  }

  @override
  void dispose() {
    widget.homeController.removeListener(_recordSample);
    super.dispose();
  }

  /// Appends one point per *stats* refresh (the controller also notifies for
  /// device-info and app-list refreshes, which must not skew the chart).
  void _recordSample() {
    final stats = widget.homeController.stats;
    if (identical(stats, _lastStatsSample)) return;
    _lastStatsSample = stats;

    if (stats.isEmpty) {
      _cpuHistory.clear();
      _memoryHistory.clear();
      return;
    }
    _push(_cpuHistory, stats.cpu?.utilisationPercent);
    _push(_memoryHistory, stats.memory?.usagePercent);
  }

  void _push(List<double> history, double? percent) {
    if (percent == null) return;
    history.add((percent / 100).clamp(0, 1));
    if (history.length > _historyLength) history.removeAt(0);
  }

  @override
  Widget buildContent(BuildContext context) {
    final session = widget.session;
    final controller = widget.homeController;
    final connected = session.isConnected;
    final info = controller.deviceInfo;
    final device = session.device;

    final detailCards = <Widget>[
      // Readiness describes live reachability, so it is dropped rather than
      // frozen while the device is away.
      if (connected && !info.developerState.isEmpty)
        ReadinessCard(device: device, developerState: info.developerState),
      HardwareCard(device: device, identity: info.identity),
      if (!info.connectivity.isEmpty || !info.cellular.isEmpty)
        ConnectivityCard(
          connectivity: info.connectivity,
          cellular: info.cellular,
        ),
      if (!info.display.isEmpty) DisplayCard(display: info.display),
      if (!info.software.isEmpty || info.identity.osVersion != null)
        SoftwareCard(software: info.software, identity: info.identity),
      if (controller.recentApps.isNotEmpty)
        RecentInstallsCard(
          apps: controller.recentApps,
          isLoading: controller.isLoadingRecentApps,
        ),
    ];

    final loadingFirstSnapshot =
        connected && controller.isLoadingDeviceInfo && controller.stats.isEmpty;
    final showSnapshot = connected || controller.hasSnapshot;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!connected) ...[
                  DisconnectedBanner(
                    device: device,
                    lastUpdatedAt: controller.lastUpdatedAt,
                    hasSnapshot: controller.hasSnapshot,
                  ),
                  const Gap(12),
                ],
                DeviceHeroCard(
                  session: session,
                  homeController: controller,
                  info: info,
                ),
                const Gap(16),
                _QuickAccessTray(
                  label: 'Quick access',
                  trailing: const CommandPaletteHint(),
                  child: QuickAccessBar(session: session),
                ),
                const Gap(12),
                if (loadingFirstSnapshot)
                  const _LoadingStrip()
                else if (showSnapshot)
                  VitalsRow(
                    battery: info.battery,
                    storage: info.storage,
                    stats: controller.stats,
                    cpuHistory: _cpuHistory,
                    memoryHistory: _memoryHistory,
                    isStale: !connected,
                  ),
                const Gap(12),
                _CardGrid(
                  children: [
                    if (!connected) ReconnectHelpCard(device: device),
                    ...detailCards,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the launcher strip in a faintly tinted, hairline-bordered tray.
///
/// The dashboard is otherwise a stack of equal-weight cards; the tray marks
/// the one band that is *actions* rather than readings. The tint is a few
/// percent of the accent over the page, which lifts the tray just above the
/// background while leaving the tiles (drawn on `surface`) sitting above it —
/// distinction by depth rather than by colour.
class const _QuickAccessTray({
  required this.label,
  required this.child,
  this.trailing,
}) extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.05),
          scheme.surfaceContainerLowest,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(label: label, trailing: trailing),
          const Gap(8),
          child,
        ],
      ),
    );
  }
}

/// Balanced multi-column layout for the detail cards — column count follows
/// the window width, cards fill round-robin so no column runs long.
class const _CardGrid({required this.children}) extends StatelessWidget {
  final List<Widget> children;

  /// Wide enough that a two-column [SpecGrid] still fits inside a card.
  static const _minColumnWidth = 360.0;
  static const _maxColumns = 3;
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            (constraints.maxWidth + _spacing) ~/ (_minColumnWidth + _spacing);
        final columnCount = fits
            .clamp(1, math.min(children.length, _maxColumns))
            .toInt();
        final columns = List.generate(columnCount, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          columns[i % columnCount].add(children[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const Gap(_spacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns[i].length; j++) ...[
                      if (j > 0) const Gap(_spacing),
                      columns[i][j],
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Small uppercase heading with an optional trailing action, used to give the
/// launcher strip a home for the command-palette hint.
class const _SectionHeading({required this.label, this.trailing})
    extends StatelessWidget {
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class const _LoadingStrip() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(12),
            Text(
              'Reading device vitals…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
