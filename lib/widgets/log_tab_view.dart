import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../controllers/log_tab_controller.dart';
import '../data/device.dart';
import '../data/log_entry.dart';
import '../services/adb_service.dart';
import '../theme/app_theme.dart';
import 'action_toolbar.dart';
import 'filter_bar.dart';
import 'log_search_bar.dart';
import 'log_viewer.dart';
import 'scroll_to_end_button.dart';

class LogTabView extends StatefulWidget {
  const LogTabView({
    super.key,
    required this.controller,
    required this.appMemoryBytesListenable,
    required this.onOpenSettings,
    required this.onShowAbout,
  });

  final LogTabController controller;
  final ValueListenable<int> appMemoryBytesListenable;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowAbout;

  @override
  State<LogTabView> createState() => _LogTabViewState();
}

class _LogTabViewState extends State<LogTabView> {
  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  LogTabController get controller => widget.controller;

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleImportLogs() async {
    final result = await controller.importLogs();
    if (!mounted || result.cancelled || result.error == null) return;
    _showSnackBar(result.error!);
  }

  Future<void> _handleExportLogs() async {
    final result = await controller.exportLogs();
    if (!mounted || result.cancelled) return;

    final message =
        result.error ??
        (result.fileName == null
            ? 'Logs exported successfully.'
            : 'Logs exported to ${result.fileName}.');
    _showSnackBar(message);
  }

  Future<void> _handleLoadDevices({bool openPickerWhenNeeded = false}) async {
    await controller.loadDevices();
    if (!mounted || !openPickerWhenNeeded) return;
    if (controller.showGetStarted) return;
    if (controller.devices.length > 1 && controller.selectedDevice == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDevicesDropdown();
      });
    }
  }

  Future<void> _showWirelessConnectionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _WirelessConnectionDialog(
          controller: controller,
          onShowSnackBar: _showSnackBar,
        );
      },
    );
  }

  Future<void> _selectDevice(Device device) {
    return controller.selectDeviceAndStart(device);
  }

  void _openDevicesDropdown() {
    _dropdownButtonKey.currentContext?.visitChildElements((element) {
      if (element.widget is Semantics) {
        element.visitChildElements((element) {
          if (element.widget is Actions) {
            element.visitChildElements((element) {
              Actions.invoke(element, ActivateIntent());
            });
          }
        });
      }
    });
  }

  Widget _buildPrimaryActionButtons({bool compact = false}) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: [
        _GetStartedActionCard(
          icon: Icons.adb,
          title: 'Select device / Load devices',
          subtitle:
              'Discover connected devices and open a live logcat session.',
          onTap: () => _handleLoadDevices(openPickerWhenNeeded: compact),
        ),
        _GetStartedActionCard(
          icon: Icons.file_download_outlined,
          title: 'Import Logs',
          subtitle: 'Open a previously exported logcat JSON file in this tab.',
          onTap: () async {
            await _handleImportLogs();
          },
        ),
        _GetStartedActionCard(
          icon: Icons.wifi_tethering,
          title: 'Wireless ADB',
          subtitle:
              'Discover nearby wireless ADB services, pair with a code, and connect over Wi‑Fi.',
          onTap: _showWirelessConnectionDialog,
        ),
      ],
    );
  }

  Widget _buildGetStartedSecondaryActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Settings',
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          tooltip: 'About',
          onPressed: widget.onShowAbout,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    );
  }

  Widget _buildLogViewer(List<LogEntry> filtered, List<int> matches) {
    final safeIndex = matches.isEmpty
        ? null
        : controller.currentSearchMatchLogIndex(matches);

    return LogViewer(
      key: ValueKey('log-viewer-${controller.logViewerRevision}'),
      logs: filtered,
      scrollController: controller.scrollController,
      wrapText: controller.wrapText,
      onLogRowTap: controller.disableAutoScroll,
      searchQuery: controller.appliedInlineSearchQuery,
      caseSensitive: controller.searchCaseSensitive,
      currentMatchLogIndex:
          controller.searchBarVisible &&
              controller.appliedInlineSearchQuery.isNotEmpty
          ? safeIndex
          : null,
      hiddenColumns: controller.hiddenColumns,
      columnWidths: controller.columnWidths,
      onHiddenColumnsChanged: controller.setHiddenColumns,
      onColumnWidthsChanged: controller.setColumnWidths,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        widget.appMemoryBytesListenable,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: controller.showGetStarted
                ? _buildGetStarted(context)
                : _buildWorkspace(context),
          ),
        );
      },
    );
  }

  Widget _buildGetStarted(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surface,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _buildGetStartedSecondaryActions(),
            ),
            Icon(
              Icons.developer_board,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const Gap(18),
            Text(
              'ADB Logcat',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const Gap(28),
            _buildPrimaryActionButtons(),
            if (controller.devices.isNotEmpty) ...[
              const Gap(28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Available devices',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Gap(12),
              SingleChildScrollView(
                child: Column(
                  children: controller.devices
                      .map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AvailableDeviceCard(
                            device: device,
                            onSelected: () => _selectDevice(device),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ] else if (controller.hasAttemptedDeviceLoad &&
                !controller.isLoadingDevices) ...[
              const Gap(28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.usb_off,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const Gap(10),
                    Text('No devices found', style: theme.textTheme.titleSmall),
                    const Gap(6),
                    Text(
                      'Connect an Android device with ADB enabled.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        if (controller.hasVisibleWorkspace)
          FilterBar(
            filterQuery: controller.searchQuery,
            controller: controller.filterController,
            focusNode: controller.filterFocusNode,
            onFilterChanged: controller.onSearchChanged,
            selectedLogLevel: controller.selectedLogLevel,
            onLogLevelChanged: (level) {
              if (level != null) {
                controller.setSelectedLogLevel(level);
              }
            },
          ),
        Expanded(
          child: controller.hasVisibleWorkspace
              ? _buildViewerArea(context)
              : _buildNoDevicePlaceholder(context),
        ),
        _buildStatusBar(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;
    final selectedValue = controller.devices.firstWhereOrNull(
      (device) => device.id == controller.selectedDevice?.id,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        spacing: 4,
        children: [
          if (controller.devices.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    DropdownButton<Device>(
                      key: _dropdownButtonKey,
                      hint: const Text('Select Device'),
                      value: selectedValue,
                      underline: const SizedBox.shrink(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 0,
                      ),
                      isDense: true,
                      borderRadius: BorderRadius.circular(8),
                      items: controller.devices
                          .map(
                            (device) => DropdownMenuItem(
                              value: device,
                              child: Text('${device.id} · ${device.model}'),
                            ),
                          )
                          .toList(),
                      onChanged: (device) {
                        if (device != null) {
                          _selectDevice(device);
                        }
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.all(0),
                      tooltip: 'Reload devices',
                      onPressed: _handleLoadDevices,
                      icon: const Icon(Icons.refresh),
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => _handleLoadDevices(openPickerWhenNeeded: true),
              icon: const Icon(Icons.usb),
              label: const Text('Load devices'),
            ),
          const Gap(4),
          IconButton(
            icon: Icon(
              Icons.play_arrow,
              color: controller.selectedDevice != null
                  ? logTheme.statusLiveColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.isRunning ? 'Restart' : 'Start',
            onPressed: controller.selectedDevice == null
                ? null
                : controller.startLogcat,
          ),
          IconButton(
            icon: Icon(
              controller.isPaused ? Icons.play_arrow : Icons.pause,
              color: controller.isRunning
                  ? logTheme.statusPausedColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.isRunning
                ? (controller.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            onPressed: controller.isRunning
                ? controller.togglePauseResume
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: controller.logs.isNotEmpty
                ? 'Clear logs'
                : 'No logs to clear',
            onPressed: controller.logs.isNotEmpty ? controller.clearLogs : null,
          ),
          IconButton(
            icon: const Icon(Icons.wifi_tethering_outlined),
            tooltip: 'Wireless ADB connect',
            onPressed: _showWirelessConnectionDialog,
          ),
          const Spacer(),
          ActionToolbar(
            isSearchBarVisible: controller.searchBarVisible,
            toggleSearchBar: controller.toggleSearchBar,
            onImport: () async {
              await _handleImportLogs();
            },
            onExport: controller.logs.isEmpty
                ? null
                : () async {
                    await _handleExportLogs();
                  },
            wrapText: controller.wrapText,
            onToggleWrap: controller.toggleWrapText,
            autoScroll: controller.autoScroll,
            onToggleAutoScroll: controller.toggleAutoScroll,
            openSettings: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildViewerArea(BuildContext context) {
    final filtered = controller.filteredLogs;
    final matches = controller.searchMatchIndices;

    return Stack(
      children: [
        _buildLogViewer(filtered, matches),
        if (controller.logs.isEmpty && controller.selectedDevice != null)
          _CenteredStateMessage(
            icon: controller.isRunning ? Icons.sync : Icons.play_circle_outline,
            title: controller.isRunning
                ? 'Waiting for logs from ${controller.selectedDevice!.displayName}'
                : 'Ready to capture logs',
            description: controller.isRunning
                ? 'Keep this tab open while logcat streams from the selected device.'
                : 'Press the play button to start streaming logcat output for the selected device.',
          ),
        if (controller.logs.isNotEmpty && filtered.isEmpty)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: context.logViewTheme.inlineNoticeBackground,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'No logs match your filter, but logs are being generated.',
                    style: TextStyle(
                      color: context.logViewTheme.inlineNoticeForeground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (controller.searchBarVisible)
          Positioned(
            top: 24,
            right: 12,
            child: LogSearchBar(
              controller: controller.searchController,
              focusNode: controller.searchFocusNode,
              caseSensitive: controller.searchCaseSensitive,
              onQueryChanged: controller.onInlineSearchChanged,
              onCaseSensitiveChanged: controller.setSearchCaseSensitive,
              onNext: controller.onSearchNext,
              onPrevious: controller.onSearchPrev,
              onClose: controller.toggleSearchBar,
              totalMatches: matches.length,
              currentMatch: matches.isEmpty
                  ? 0
                  : controller.searchCurrentMatch + 1,
            ),
          ),
        ListenableBuilder(
          listenable: controller.scrollController,
          builder: (context, child) {
            return ScrollToEndButton(
              visible:
                  controller.logs.isNotEmpty &&
                  controller.scrollController.hasClients &&
                  controller.scrollController.offset <
                      (controller.scrollController.position.maxScrollExtent -
                          24),
              onPressed: controller.scrollToEnd,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoDevicePlaceholder(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _CenteredStateMessage(
          icon: Icons.devices_outlined,
          title: 'No device or imported logs in this tab',
          description:
              'Load connected devices to begin a live session, or import a saved log file into this workspace.',
          footer: _buildPrimaryActionButtons(compact: true),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final logTheme = context.logViewTheme;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            'Logs: ${controller.logs.length}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Filtered: ${controller.filteredLogs.length}',
            style: logTheme.statusBarStyle,
          ),
          const Spacer(),
          Text(
            'App mem: ${controller.formatBytes(widget.appMemoryBytesListenable.value)}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Logs mem: ${controller.formatBytes(controller.totalLogsMemoryBytes)}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(8),
          _buildLogLinesEditor(context),
          const Gap(8),
          SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
          const Gap(8),
          Text(
            controller.isPaused
                ? 'Paused'
                : controller.isRunning
                ? 'Live'
                : 'Stopped',
            style: TextStyle(
              color: controller.isPaused
                  ? logTheme.statusPausedColor
                  : controller.isRunning
                  ? logTheme.statusLiveColor
                  : logTheme.statusStoppedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLinesEditor(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: controller.editingLogLinesLimit
          ? null
          : BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: !controller.editingLogLinesLimit
          ? InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => controller.setEditingLogLinesLimit(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Max lines: ${controller.logLinesLimit}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicWidth(
                  child: TextField(
                    onTapOutside: (_) =>
                        controller.setEditingLogLinesLimit(false),
                    controller: controller.logLinesController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      prefixText: 'Max lines: ',
                      border: OutlineInputBorder(),
                      suffix: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: controller.submitLogLinesLimit,
                        icon: const Icon(Icons.check, size: 14),
                      ),
                    ),
                    onSubmitted: controller.submitLogLinesLimit,
                    onEditingComplete: () =>
                        controller.setEditingLogLinesLimit(false),
                  ),
                ),
              ],
            ),
    );
  }
}

class _WirelessConnectionDialog extends StatefulWidget {
  const _WirelessConnectionDialog({
    required this.controller,
    required this.onShowSnackBar,
  });

  final LogTabController controller;
  final ValueChanged<String> onShowSnackBar;

  @override
  State<_WirelessConnectionDialog> createState() =>
      _WirelessConnectionDialogState();
}

class _WirelessConnectionDialogState extends State<_WirelessConnectionDialog> {
  late final TextEditingController _pairAddressController;
  late final TextEditingController _pairingCodeController;
  late final TextEditingController _connectAddressController;
  var _section = _WirelessDialogSection.nearby;
  String? _selectedDiscoveryHost;

  LogTabController get controller => widget.controller;

  List<_DiscoveredWirelessTarget> get _discoveredTargets {
    final groupedServices = <String, List<AdbMdnsService>>{};
    for (final service in controller.wirelessServices) {
      groupedServices.putIfAbsent(service.host, () => []).add(service);
    }

    final targets = groupedServices.entries.map((entry) {
      final pairingService = entry.value.firstWhereOrNull(
        (service) => service.type == AdbMdnsServiceType.pairing,
      );
      final connectService = entry.value.firstWhereOrNull(
        (service) => service.type == AdbMdnsServiceType.connect,
      );

      return _DiscoveredWirelessTarget(
        host: entry.key,
        pairingService: pairingService,
        connectService: connectService,
      );
    }).toList();

    targets.sort((left, right) => left.host.compareTo(right.host));
    return targets;
  }

  _DiscoveredWirelessTarget? get _selectedDiscoveryTarget {
    if (_selectedDiscoveryHost != null) {
      return _discoveredTargets.firstWhereOrNull(
        (target) => target.host == _selectedDiscoveryHost,
      );
    }

    final pairingHost = _hostFromAddress(_pairAddressController.text);
    if (pairingHost != null) {
      return _discoveredTargets.firstWhereOrNull(
        (target) => target.host == pairingHost,
      );
    }

    final connectHost = _hostFromAddress(_connectAddressController.text);
    if (connectHost != null) {
      return _discoveredTargets.firstWhereOrNull(
        (target) => target.host == connectHost,
      );
    }

    return _discoveredTargets.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _pairAddressController = TextEditingController(
      text: controller.suggestedWirelessPairingAddress ?? '',
    );
    _pairingCodeController = TextEditingController();
    _connectAddressController = TextEditingController(
      text: controller.suggestedWirelessConnectAddress ?? '',
    );
  }

  @override
  void dispose() {
    _pairAddressController.dispose();
    _pairingCodeController.dispose();
    _connectAddressController.dispose();
    super.dispose();
  }

  Future<void> _handleDiscover() async {
    final result = await controller.discoverWirelessServices();
    if (!mounted) return;

    _applySuggestedAddresses(preferFirstDiscoveredTarget: true);
    if (!result.isSuccess && result.error != null) {
      widget.onShowSnackBar(result.error!);
    }
  }

  Future<void> _handlePair() async {
    final result = await controller.pairWirelessDevice(
      address: _pairAddressController.text,
      pairingCode: _pairingCodeController.text,
    );
    if (!mounted) return;

    if (result.error != null) {
      widget.onShowSnackBar(result.error!);
      return;
    }

    if (result.message != null) {
      widget.onShowSnackBar(result.message!);
    }
    _applySuggestedAddresses();
  }

  Future<void> _handleConnect() async {
    final result = await controller.connectWirelessDevice(
      address: _connectAddressController.text,
    );
    if (!mounted) return;

    final feedback = result.error ?? result.message;
    if (feedback != null && feedback.isNotEmpty) {
      widget.onShowSnackBar(feedback);
    }
    if (result.isSuccess) {
      Navigator.of(context).pop();
    }
  }

  void _applySuggestedAddresses({bool preferFirstDiscoveredTarget = false}) {
    final suggestedPairing = controller.suggestedWirelessPairingAddress;
    final suggestedConnect = controller.suggestedWirelessConnectAddress;
    final firstTarget = _discoveredTargets.firstOrNull;

    setState(() {
      if (_pairAddressController.text.trim().isEmpty &&
          suggestedPairing != null) {
        _pairAddressController.text = suggestedPairing;
      }
      if (_connectAddressController.text.trim().isEmpty &&
          suggestedConnect != null) {
        _connectAddressController.text = suggestedConnect;
      }

      _selectedDiscoveryHost ??=
          _hostFromAddress(suggestedPairing) ??
          _hostFromAddress(suggestedConnect) ??
          (preferFirstDiscoveredTarget ? firstTarget?.host : null);
    });
  }

  void _selectDiscoveredTarget(_DiscoveredWirelessTarget target) {
    final matchingConnectService = target.connectService;

    setState(() {
      _selectedDiscoveryHost = target.host;
      if (target.pairingService != null) {
        _pairAddressController.text = target.pairingService!.address;
      }
      if (matchingConnectService != null) {
        _connectAddressController.text = matchingConnectService.address;
      }
    });
  }

  String? _hostFromAddress(String? address) {
    if (address == null) return null;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    final separatorIndex = trimmed.lastIndexOf(':');
    if (separatorIndex <= 0) return null;
    return trimmed.substring(0, separatorIndex);
  }

  Widget _buildNearbyDevicesTab(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTarget = _selectedDiscoveryTarget;

    if (_discoveredTargets.isEmpty) {
      final description = controller.hasAttemptedWirelessDiscovery
          ? 'No nearby wireless ADB devices were discovered. You can try discovery again or switch to manual entry.'
          : 'Start by discovering nearby wireless ADB devices advertised through mDNS.';

      return _WirelessPlaceholderCard(
        icon: controller.hasAttemptedWirelessDiscovery
            ? Icons.wifi_find
            : Icons.travel_explore,
        title: controller.hasAttemptedWirelessDiscovery
            ? 'No nearby devices found'
            : 'Discover nearby devices',
        description: description,
        footer: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: controller.isWirelessBusy ? null : _handleDiscover,
              icon: controller.isDiscoveringWireless
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.travel_explore),
              label: Text(
                controller.hasAttemptedWirelessDiscovery
                    ? 'Refresh discovery'
                    : 'Discover devices',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _section = _WirelessDialogSection.manual;
                });
              },
              icon: const Icon(Icons.tune),
              label: const Text('Manual entry'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nearby devices', style: theme.textTheme.titleMedium),
        const Gap(6),
        Text(
          'Pick a discovered device first. Pairing and connect actions will adapt to the selected device.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final target in _discoveredTargets)
              _WirelessDiscoveryCard(
                target: target,
                selected: selectedTarget?.host == target.host,
                onTap: () => _selectDiscoveredTarget(target),
              ),
          ],
        ),
        const Gap(18),
        if (selectedTarget != null)
          _WirelessSelectedDevicePanel(
            target: selectedTarget,
            pairingCodeController: _pairingCodeController,
            pairingBusy: controller.isPairingWireless,
            connectingBusy: controller.isConnectingWireless,
            actionsDisabled: controller.isWirelessBusy,
            onPair: selectedTarget.pairingService == null ? null : _handlePair,
            onConnect: selectedTarget.connectService == null
                ? null
                : _handleConnect,
            onUseManualEntry: () {
              setState(() {
                _section = _WirelessDialogSection.manual;
              });
            },
          ),
      ],
    );
  }

  Widget _buildManualEntryTab(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Manual entry', style: theme.textTheme.titleMedium),
        const Gap(6),
        Text(
          'Use this only when discovery is unavailable or you already know the pairing and connect addresses.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(16),
        _WirelessManualSection(
          title: 'Pair with code',
          description:
              'Enter the pairing address from the device screen and the pairing code shown on the device.',
          child: Column(
            children: [
              TextField(
                controller: _pairAddressController,
                enabled: !controller.isWirelessBusy,
                decoration: const InputDecoration(
                  labelText: 'Pairing address',
                  hintText: '192.168.0.104:45673',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
              ),
              const Gap(12),
              TextField(
                controller: _pairingCodeController,
                enabled: !controller.isWirelessBusy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  hintText: 'Enter the 6-digit code shown on the device',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
                onSubmitted: (_) {
                  if (!controller.isWirelessBusy) {
                    _handlePair();
                  }
                },
              ),
              const Gap(12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: controller.isWirelessBusy ? null : _handlePair,
                  icon: controller.isPairingWireless
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: const Text('Pair'),
                ),
              ),
            ],
          ),
        ),
        const Gap(16),
        _WirelessManualSection(
          title: 'Connect and start logcat',
          description:
              'After pairing, enter the connect address advertised by ADB and open the live session in this tab.',
          child: Column(
            children: [
              TextField(
                controller: _connectAddressController,
                enabled: !controller.isWirelessBusy,
                decoration: const InputDecoration(
                  labelText: 'Connect address',
                  hintText: '192.168.0.117:37251',
                  prefixIcon: Icon(Icons.link_outlined),
                ),
                onSubmitted: (_) {
                  if (!controller.isWirelessBusy) {
                    _handleConnect();
                  }
                },
              ),
              const Gap(12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: controller.isWirelessBusy ? null : _handleConnect,
                  child: controller.isConnectingWireless
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect and start logcat'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Icon(Icons.wifi_tethering, color: theme.colorScheme.primary),
              const Gap(12),
              const Expanded(child: Text('Wireless ADB')),
            ],
          ),
          content: SizedBox(
            width: 720,
            height: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover nearby devices first, then pair and connect with just the relevant fields for the selected device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Gap(16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<_WirelessDialogSection>(
                      segments: const [
                        ButtonSegment<_WirelessDialogSection>(
                          value: _WirelessDialogSection.nearby,
                          icon: Icon(Icons.wifi_find_outlined),
                          label: Text('Nearby devices'),
                        ),
                        ButtonSegment<_WirelessDialogSection>(
                          value: _WirelessDialogSection.manual,
                          icon: Icon(Icons.tune),
                          label: Text('Manual entry'),
                        ),
                      ],
                      selected: {_section},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _section = selection.first;
                        });
                      },
                    ),
                    FilledButton.tonalIcon(
                      onPressed: controller.isWirelessBusy
                          ? null
                          : _handleDiscover,
                      icon: controller.isDiscoveringWireless
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.travel_explore),
                      label: Text(
                        controller.hasAttemptedWirelessDiscovery
                            ? 'Refresh discovery'
                            : 'Discover nearby',
                      ),
                    ),
                    if (controller.selectedDevice != null)
                      Text(
                        'Current device: ${controller.selectedDevice!.displayName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const Gap(16),
                _WirelessFeedbackBanner(
                  message: controller.wirelessMessage,
                  error: controller.wirelessError,
                ),
                const Gap(16),
                Flexible(
                  child: SingleChildScrollView(
                    child: _section == _WirelessDialogSection.nearby
                        ? _buildNearbyDevicesTab(context)
                        : _buildManualEntryTab(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

enum _WirelessDialogSection { nearby, manual }

class _DiscoveredWirelessTarget {
  const _DiscoveredWirelessTarget({
    required this.host,
    this.pairingService,
    this.connectService,
  });

  final String host;
  final AdbMdnsService? pairingService;
  final AdbMdnsService? connectService;

  String get title => pairingService?.name ?? connectService?.name ?? host;
  String? get pairingAddress => pairingService?.address;
  String? get connectAddress => connectService?.address;
  bool get canPair => pairingService != null;
  bool get canConnect => connectService != null;
}

class _WirelessFeedbackBanner extends StatelessWidget {
  const _WirelessFeedbackBanner({this.message, this.error});

  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = error ?? message;
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    final isError = error != null;
    final background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: foreground,
            size: 18,
          ),
          const Gap(10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _WirelessPlaceholderCard extends StatelessWidget {
  const _WirelessPlaceholderCard({
    required this.icon,
    required this.title,
    required this.description,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const Gap(12),
          Text(title, style: theme.textTheme.titleMedium),
          const Gap(8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (footer != null) ...[const Gap(16), footer!],
        ],
      ),
    );
  }
}

class _WirelessDiscoveryCard extends StatelessWidget {
  const _WirelessDiscoveryCard({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final _DiscoveredWirelessTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 320,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phone_android,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        target.host,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                ),
                const Gap(10),
                Text(
                  target.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (target.pairingAddress != null)
                      Chip(
                        avatar: const Icon(Icons.password, size: 16),
                        label: Text('Pair ${target.pairingAddress}'),
                      ),
                    if (target.connectAddress != null)
                      Chip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: Text('Connect ${target.connectAddress}'),
                      ),
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

class _WirelessSelectedDevicePanel extends StatelessWidget {
  const _WirelessSelectedDevicePanel({
    required this.target,
    required this.pairingCodeController,
    required this.pairingBusy,
    required this.connectingBusy,
    required this.actionsDisabled,
    required this.onPair,
    required this.onConnect,
    required this.onUseManualEntry,
  });

  final _DiscoveredWirelessTarget target;
  final TextEditingController pairingCodeController;
  final bool pairingBusy;
  final bool connectingBusy;
  final bool actionsDisabled;
  final VoidCallback? onPair;
  final VoidCallback? onConnect;
  final VoidCallback onUseManualEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected device', style: theme.textTheme.titleMedium),
          const Gap(8),
          Text(target.host, style: theme.textTheme.bodyLarge),
          const Gap(12),
          if (target.pairingAddress != null)
            _WirelessDetailRow(
              icon: Icons.password,
              label: 'Pairing address',
              value: target.pairingAddress!,
            ),
          if (target.connectAddress != null)
            _WirelessDetailRow(
              icon: Icons.link,
              label: 'Connect address',
              value: target.connectAddress!,
            ),
          if (target.canPair) ...[
            const Gap(14),
            TextField(
              controller: pairingCodeController,
              enabled: !actionsDisabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                hintText: 'Enter the code shown on the device',
                prefixIcon: Icon(Icons.password_outlined),
              ),
              onSubmitted: (_) {
                if (!actionsDisabled && onPair != null) {
                  onPair!();
                }
              },
            ),
          ],
          const Gap(16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (target.canPair)
                FilledButton.icon(
                  onPressed: actionsDisabled ? null : onPair,
                  icon: pairingBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: const Text('Pair'),
                ),
              FilledButton.tonalIcon(
                onPressed: actionsDisabled || !target.canConnect
                    ? null
                    : onConnect,
                icon: connectingBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: const Text('Connect'),
              ),
              TextButton.icon(
                onPressed: onUseManualEntry,
                icon: const Icon(Icons.tune),
                label: const Text('Manual entry'),
              ),
            ],
          ),
          if (!target.canConnect) ...[
            const Gap(12),
            Text(
              'A connect endpoint was not discovered for this device yet. If needed, switch to manual entry after pairing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WirelessManualSection extends StatelessWidget {
  const _WirelessManualSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const Gap(6),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(14),
          child,
        ],
      ),
    );
  }
}

class _WirelessDetailRow extends StatelessWidget {
  const _WirelessDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const Gap(8),
          Text(
            '$label: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AvailableDeviceCard extends StatelessWidget {
  const _AvailableDeviceCard({required this.device, required this.onSelected});

  final Device device;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelected,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_android, color: theme.colorScheme.primary),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.displayName, style: theme.textTheme.titleSmall),
                    const Gap(4),
                    Text(
                      '${device.id} · ${device.status}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GetStartedActionCard extends StatelessWidget {
  const _GetStartedActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;

    return SizedBox(
      width: 320,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  color: logTheme.cardShadowColor,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const Gap(14),
                Text(title, style: theme.textTheme.titleMedium),
                const Gap(8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _CenteredStateMessage extends StatelessWidget {
  const _CenteredStateMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const Gap(16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (footer != null) ...[const Gap(20), footer!],
          ],
        ),
      ),
    );
  }
}
