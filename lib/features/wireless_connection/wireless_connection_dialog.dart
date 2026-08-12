import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../data/device.dart';
import 'data/wireless_debug_models.dart';
import '../../session/device_session_manager.dart';
import '../../presentation/components/eagly_dialog.dart';
import 'components/discovered_wireless_target.dart';
import 'components/wireless_discovery_card.dart';
import 'components/wireless_feedback_banner.dart';
import 'components/wireless_manual_section.dart';
import 'components/wireless_placeholder_card.dart';
import 'components/wireless_qr_panel.dart';
import 'components/wireless_selected_device_panel.dart';
import 'wireless_connection_controller.dart';

class WirelessConnectionDialog extends StatefulWidget {
  const WirelessConnectionDialog({
    super.key,
    required this.manager,
    required this.onShowSnackBar,
  });

  final DeviceSessionManager manager;
  final ValueChanged<String> onShowSnackBar;

  @override
  State<WirelessConnectionDialog> createState() =>
      _WirelessConnectionDialogState();
}

class _WirelessConnectionDialogState extends State<WirelessConnectionDialog> {
  late final TextEditingController _pairAddressController;
  late final TextEditingController _pairingCodeController;
  late final TextEditingController _connectAddressController;
  late final wirelessController = WirelessConnectionController(
    devicesRepository: manager.repository,
    onDevicesApplied: (_) async {},
    onActivateDevice: (device) async => manager.select(device.id),
    selectedDeviceIdProvider: () => manager.selectedId,
    isRunningProvider: () {
      final session = manager.selected;
      return session != null &&
          session.isActivated &&
          (session.logSessionManager.selectedTab?.isRunning ?? false);
    },
  );

  var _section = _WirelessDialogSection.nearby;
  String? _selectedDiscoveryHost;
  String? _fallbackConnectHost;
  var _showManualConnectSection = false;

  DeviceSessionManager get manager => widget.manager;

  List<DiscoveredWirelessTarget> get _discoveredTargets {
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

          return DiscoveredWirelessTarget(
            host: entry.key,
            pairingService: pairingService,
            connectServices: connectServices,
          );
        })
        .toList(growable: false);

    return targets.sortedBy<String>((target) => target.host);
  }

  DiscoveredWirelessTarget? get _selectedDiscoveryTarget {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoDiscoverNearby();
    });
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

  void _maybeAutoDiscoverNearby() {
    if (!wirelessController.isWirelessBusy) {
      _handleDiscover();
    }
  }

  void _maybeAutoGenerateQr() {
    if (wirelessController.qrSession == null &&
        !wirelessController.isWaitingForQrScan &&
        !wirelessController.isWirelessBusy) {
      _handleQrPair();
    }
  }

  void _onSectionChanged(_WirelessDialogSection next) {
    wirelessController.cancelAllOperations();
    setState(() {
      _section = next;
    });
    if (next == _WirelessDialogSection.nearby) {
      _maybeAutoDiscoverNearby();
    } else if (next == _WirelessDialogSection.qr) {
      _maybeAutoGenerateQr();
    }
  }

  Future<void> _handleQrPair() async {
    final result = await wirelessController.startQrPairing();
    if (!mounted || result == null) return;

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

    if (result.connectAddresses.isNotEmpty) {
      _connectAddressController.text = result.connectAddresses.first;
    }
    setState(() {
      _section = _WirelessDialogSection.manual;
      _showManualConnectSection = true;
    });
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

  void _selectDiscoveredTarget(DiscoveredWirelessTarget target) {
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

  Device? _connectedDeviceForTarget(DiscoveredWirelessTarget target) {
    return manager.devices.firstWhereOrNull(
      (device) =>
          device.status == 'device' &&
          _hostFromAddress(device.id) == target.host,
    );
  }

  Device? _connectedDeviceForAddress(String address) {
    final host = _hostFromAddress(address);
    if (host == null) return null;
    return manager.devices.firstWhereOrNull(
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

      return WirelessPlaceholderCard(
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
        const Gap(12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final target in _discoveredTargets)
              WirelessDiscoveryCard(
                target: target,
                selected: selectedTarget?.host == target.host,
                onTap: () => _selectDiscoveredTarget(target),
              ),
          ],
        ),
        const Gap(18),
        if (selectedTarget != null)
          WirelessSelectedDevicePanel(
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

  Widget _buildQrCodeTab(BuildContext context) {
    final theme = Theme.of(context);
    final session = wirelessController.qrSession;
    final waiting = wirelessController.isWaitingForQrScan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pair with QR code', style: theme.textTheme.titleMedium),
        const Gap(6),
        Text(
          'On your Android device open Settings → Developer options → Wireless '
          'debugging → Pair device with QR code, then scan the code below. '
          'Both devices must be on the same network.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(18),
        Center(
          child: WirelessQrPanel(
            payload: session?.payload,
            waiting: waiting,
            busy: wirelessController.isWirelessBusy,
            onGenerate: _handleQrPair,
            onCancel: wirelessController.cancelQrPairing,
          ),
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
        WirelessManualSection(
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
                  onPressed: wirelessController.isWirelessBusy
                      ? null
                      : _handlePair,
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
          WirelessManualSection(
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
      animation: Listenable.merge([manager, wirelessController]),
      builder: (context, _) {
        return EaglyDialog(
          title: 'Wireless ADB',
          icon: Icons.wifi_tethering,
          width: 720,
          height: 560,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        value: _WirelessDialogSection.qr,
                        icon: Icon(Icons.qr_code_2),
                        label: Text('QR code'),
                      ),
                      ButtonSegment<_WirelessDialogSection>(
                        value: _WirelessDialogSection.manual,
                        icon: Icon(Icons.tune),
                        label: Text('Manual entry'),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: (selection) {
                      _onSectionChanged(selection.first);
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
                  if (manager.selected != null)
                    Text(
                      'Current device: ${manager.selected!.device.displayName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const Gap(14),
              WirelessFeedbackBanner(
                message: wirelessController.wirelessMessage,
                error: wirelessController.wirelessError,
              ),
              const Gap(14),
              Flexible(
                child: SingleChildScrollView(
                  child: switch (_section) {
                    _WirelessDialogSection.nearby => _buildNearbyDevicesTab(
                      context,
                    ),
                    _WirelessDialogSection.qr => _buildQrCodeTab(context),
                    _WirelessDialogSection.manual => _buildManualEntryTab(
                      context,
                    ),
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _WirelessDialogSection { nearby, qr, manual }
