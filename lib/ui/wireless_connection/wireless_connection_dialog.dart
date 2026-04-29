import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../log_tab_view/log_tab_controller.dart';
import 'wireless_connection_controller.dart';
import '../../data/device.dart';
import '../../data/wireless_debug_models.dart';

class WirelessConnectionDialog extends StatefulWidget {
  const WirelessConnectionDialog({
    super.key,
    required this.controller,
    required this.wirelessController,
    required this.onShowSnackBar,
  });

  final LogTabController controller;
  final WirelessConnectionController wirelessController;
  final ValueChanged<String> onShowSnackBar;

  @override
  State<WirelessConnectionDialog> createState() =>
      _WirelessConnectionDialogState();
}

class _WirelessConnectionDialogState extends State<WirelessConnectionDialog> {
  late final TextEditingController _pairAddressController;
  late final TextEditingController _pairingCodeController;
  late final TextEditingController _connectAddressController;

  var _section = _WirelessDialogSection.nearby;
  String? _selectedDiscoveryHost;
  String? _fallbackConnectHost;
  var _showManualConnectSection = false;

  LogTabController get controller => widget.controller;
  WirelessConnectionController get wirelessController =>
      widget.wirelessController;

  List<_DiscoveredWirelessTarget> get _discoveredTargets {
    final groupedServices = <String, List<WirelessDebugService>>{};
    for (final service in wirelessController.wirelessServices) {
      groupedServices.putIfAbsent(service.host, () => []).add(service);
    }

    final targets = groupedServices.entries
        .map((entry) {
          final pairingService = entry.value.firstWhereOrNull(
            (service) => service.type == WirelessDebugServiceType.pairing,
          );
          final connectServices = entry.value
              .where(
                (service) => service.type == WirelessDebugServiceType.connect,
              )
              .sortedBy<num>((service) => service.port)
              .toList(growable: false);

          return _DiscoveredWirelessTarget(
            host: entry.key,
            pairingService: pairingService,
            connectServices: connectServices,
          );
        })
        .toList(growable: false);

    return targets.sortedBy<String>((target) => target.host);
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
      text: wirelessController.suggestedWirelessPairingAddress ?? '',
    );
    _pairingCodeController = TextEditingController();
    _connectAddressController = TextEditingController(
      text: wirelessController.suggestedWirelessConnectAddress ?? '',
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
    final result = await wirelessController.discoverWirelessServices();
    if (!mounted) return;

    _applySuggestedAddresses(preferFirstDiscoveredTarget: true);
    if (!result.isSuccess && result.error != null) {
      widget.onShowSnackBar(result.error!);
    }
  }

  Future<void> _handlePair() async {
    final selectedTarget = _selectedDiscoveryTarget;
    final result = await wirelessController.pairWirelessDevice(
      address: _pairAddressController.text,
      pairingCode: _pairingCodeController.text,
      connectAddresses:
          selectedTarget?.connectAddresses ?? _manualConnectAddresses,
    );
    if (!mounted) return;

    if (result.connectAddresses.isNotEmpty) {
      _connectAddressController.text = result.connectAddresses.first;
    }

    setState(() {
      if (result.shouldShowConnectAction) {
        _showManualConnectSection = true;
        _fallbackConnectHost =
            selectedTarget?.host ??
            _hostFromAddress(_connectAddressController.text);
      } else {
        _fallbackConnectHost = null;
      }
    });

    if (result.error != null) {
      widget.onShowSnackBar(result.error!);
      return;
    }

    if (result.message != null) {
      widget.onShowSnackBar(result.message!);
    }
    if (result.autoConnected) {
      Navigator.of(context).pop();
      return;
    }

    _applySuggestedAddresses();
  }

  Future<void> _handleConnect() async {
    final selectedTarget = _selectedDiscoveryTarget;
    final result = await wirelessController.connectWirelessDevice(
      address: _connectAddressController.text,
      candidateAddresses:
          selectedTarget?.connectAddresses ?? _manualConnectAddresses,
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

  List<String> get _manualConnectAddresses {
    final address = _connectAddressController.text.trim();
    return address.isEmpty ? const [] : [address];
  }

  void _applySuggestedAddresses({bool preferFirstDiscoveredTarget = false}) {
    final suggestedPairing = wirelessController.suggestedWirelessPairingAddress;
    final suggestedConnect = wirelessController.suggestedWirelessConnectAddress;
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
    setState(() {
      _selectedDiscoveryHost = target.host;
      _fallbackConnectHost = null;
      if (target.pairingService != null) {
        _pairAddressController.text = target.pairingService!.address;
      }
      if (target.primaryConnectAddress != null) {
        _connectAddressController.text = target.primaryConnectAddress!;
      }
    });
  }

  Device? _connectedDeviceForTarget(_DiscoveredWirelessTarget target) {
    return controller.devices.firstWhereOrNull(
      (device) =>
          device.status == 'device' &&
          _hostFromAddress(device.id) == target.host,
    );
  }

  Device? _connectedDeviceForAddress(String address) {
    final host = _hostFromAddress(address);
    if (host == null) return null;
    return controller.devices.firstWhereOrNull(
      (device) =>
          device.status == 'device' && _hostFromAddress(device.id) == host,
    );
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
      final description = wirelessController.hasAttemptedWirelessDiscovery
          ? 'No nearby wireless ADB devices were discovered. You can try discovery again or switch to manual entry.'
          : 'Start by discovering nearby wireless ADB devices advertised through mDNS.';

      return _WirelessPlaceholderCard(
        icon: wirelessController.hasAttemptedWirelessDiscovery
            ? Icons.wifi_find
            : Icons.travel_explore,
        title: wirelessController.hasAttemptedWirelessDiscovery
            ? 'No nearby devices found'
            : 'Discover nearby devices',
        description: description,
        footer: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: wirelessController.isWirelessBusy ? null : _handleDiscover,
              icon: wirelessController.isDiscoveringWireless
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.travel_explore),
              label: Text(
                wirelessController.hasAttemptedWirelessDiscovery
                    ? 'Refresh discovery'
                    : 'Discover devices',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _section = _WirelessDialogSection.manual;
                  _showManualConnectSection = true;
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
          'Pick a discovered device first. Pairing will continue into connection automatically when a connect port is available.',
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
            connectedDevice: _connectedDeviceForTarget(selectedTarget),
            pairingCodeController: _pairingCodeController,
            pairingBusy: wirelessController.isPairingWireless,
            connectingBusy: wirelessController.isConnectingWireless,
            actionsDisabled: wirelessController.isWirelessBusy,
            showConnectAction:
                selectedTarget.canConnect &&
                (_fallbackConnectHost == selectedTarget.host ||
                    !selectedTarget.canPair ||
                    _connectedDeviceForTarget(selectedTarget) != null),
            onPair: selectedTarget.pairingService == null ? null : _handlePair,
            onConnect: selectedTarget.canConnect ? _handleConnect : null,
            onUseManualEntry: () {
              setState(() {
                _section = _WirelessDialogSection.manual;
                _showManualConnectSection = true;
              });
            },
          ),
      ],
    );
  }

  Widget _buildManualEntryTab(BuildContext context) {
    final theme = Theme.of(context);
    final manualConnectAddress = _connectAddressController.text.trim();
    final connectedDevice = _connectedDeviceForAddress(manualConnectAddress);

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
          title: _manualConnectAddresses.isNotEmpty
              ? 'Pair and connect'
              : 'Pair with code',
          description:
              'Enter the pairing address from the device screen and the pairing code shown on the device. If a connect address is available, connection will continue automatically.',
          child: Column(
            children: [
              TextField(
                controller: _pairAddressController,
                enabled: !wirelessController.isWirelessBusy,
                decoration: const InputDecoration(
                  labelText: 'Pairing address',
                  hintText: '192.168.0.104:45673',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
              ),
              const Gap(12),
              TextField(
                controller: _pairingCodeController,
                enabled: !wirelessController.isWirelessBusy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  hintText: 'Enter the 6-digit code shown on the device',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
                onSubmitted: (_) {
                  if (!wirelessController.isWirelessBusy) {
                    _handlePair();
                  }
                },
              ),
              const Gap(12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: wirelessController.isWirelessBusy ? null : _handlePair,
                  icon: wirelessController.isPairingWireless
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(
                    _manualConnectAddresses.isNotEmpty
                        ? 'Pair and connect'
                        : 'Pair',
                  ),
                ),
              ),
            ],
          ),
        ),
        const Gap(12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _showManualConnectSection = !_showManualConnectSection;
              });
            },
            icon: Icon(
              _showManualConnectSection ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(
              _showManualConnectSection
                  ? 'Hide manual connect'
                  : 'Already paired? Connect manually',
            ),
          ),
        ),
        if (_showManualConnectSection) ...[
          const Gap(4),
          _WirelessManualSection(
            title: connectedDevice != null
                ? 'Use connected device'
                : 'Connect and start logcat',
            description: connectedDevice != null
                ? 'This wireless device is already connected. Reuse the existing connection instead of reconnecting.'
                : 'Use this only when automatic connection could not finish or the device was paired previously.',
            child: Column(
              children: [
                TextField(
                  controller: _connectAddressController,
                  enabled: !wirelessController.isWirelessBusy,
                  decoration: const InputDecoration(
                    labelText: 'Connect address',
                    hintText: '192.168.0.117:37251',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  onSubmitted: (_) {
                    if (!wirelessController.isWirelessBusy) {
                      _handleConnect();
                    }
                  },
                ),
                const Gap(12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: wirelessController.isWirelessBusy
                        ? null
                        : _handleConnect,
                    child: wirelessController.isConnectingWireless
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            connectedDevice != null
                                ? 'Use connected device'
                                : 'Connect and start logcat',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([controller, wirelessController]),
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
                  'Discover nearby devices first, then pair and connect with only the relevant actions shown for the selected device.',
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
                      onPressed: wirelessController.isWirelessBusy
                          ? null
                          : _handleDiscover,
                      icon: wirelessController.isDiscoveringWireless
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.travel_explore),
                      label: Text(
                        wirelessController.hasAttemptedWirelessDiscovery
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
                  message: wirelessController.wirelessMessage,
                  error: wirelessController.wirelessError,
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
    this.connectServices = const [],
  });

  final String host;
  final WirelessDebugService? pairingService;
  final List<WirelessDebugService> connectServices;

  String get title =>
      pairingService?.name ?? connectServices.firstOrNull?.name ?? host;
  String? get pairingAddress => pairingService?.address;
  String? get primaryConnectAddress => connectServices.firstOrNull?.address;
  List<String> get connectAddresses =>
      connectServices.map((service) => service.address).toList(growable: false);
  bool get canPair => pairingService != null;
  bool get canConnect => connectServices.isNotEmpty;

  String get connectSummary {
    if (connectServices.isEmpty) return 'No connect ports discovered';
    if (connectServices.length == 1) {
      return 'Connect ${connectServices.single.address}';
    }
    return '${connectServices.length} connect ports';
  }
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
                        label: Text(target.pairingAddress!),
                      ),
                    if (target.canConnect)
                      Chip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: Text(target.connectSummary),
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
    required this.connectedDevice,
    required this.pairingCodeController,
    required this.pairingBusy,
    required this.connectingBusy,
    required this.actionsDisabled,
    required this.showConnectAction,
    required this.onPair,
    required this.onConnect,
    required this.onUseManualEntry,
  });

  final _DiscoveredWirelessTarget target;
  final Device? connectedDevice;
  final TextEditingController pairingCodeController;
  final bool pairingBusy;
  final bool connectingBusy;
  final bool actionsDisabled;
  final bool showConnectAction;
  final VoidCallback? onPair;
  final VoidCallback? onConnect;
  final VoidCallback onUseManualEntry;

  bool get _alreadyConnected => connectedDevice != null;

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
          if (_alreadyConnected) ...[
            const Gap(6),
            Text(
              'Already connected as ${connectedDevice!.id}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Gap(12),
          if (target.pairingAddress != null)
            _WirelessDetailRow(
              icon: Icons.password,
              label: 'Pairing address',
              value: target.pairingAddress!,
            ),
          if (target.connectAddresses.isNotEmpty)
            _WirelessDetailRow(
              icon: Icons.link,
              label: target.connectAddresses.length == 1
                  ? 'Connect address'
                  : 'Connect ports',
              value: target.connectAddresses.join(', '),
            ),
          if (target.canPair && !_alreadyConnected) ...[
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
              if (target.canPair && !_alreadyConnected)
                FilledButton.icon(
                  onPressed: actionsDisabled ? null : onPair,
                  icon: pairingBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(target.canConnect ? 'Pair and connect' : 'Pair'),
                ),
              if ((!target.canPair && target.canConnect) ||
                  showConnectAction ||
                  _alreadyConnected)
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
                  label: Text(
                    _alreadyConnected ? 'Use connected device' : 'Connect',
                  ),
                ),
              TextButton.icon(
                onPressed: onUseManualEntry,
                icon: const Icon(Icons.tune),
                label: const Text('Manual entry'),
              ),
            ],
          ),
          if (showConnectAction && !_alreadyConnected) ...[
            const Gap(12),
            Text(
              'Automatic connect did not complete, so you can retry connect explicitly for this device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (!target.canConnect) ...[
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
