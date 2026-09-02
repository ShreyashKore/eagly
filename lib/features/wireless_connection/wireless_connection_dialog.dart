import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../data/device.dart';
import 'data/wireless_debug_models.dart';
import '../../session/device_session_manager.dart';
import '../../presentation/components/delayed_reveal.dart';
import '../../presentation/components/eagly_dialog.dart';
import '../../presentation/components/hint_note.dart';
import 'components/discovered_wireless_target.dart';
import 'components/wireless_discovery_card.dart';
import 'components/wireless_feedback_banner.dart';
import 'components/wireless_manual_section.dart';
import 'components/wireless_qr_panel.dart';
import 'components/wireless_selected_device_panel.dart';
import 'wireless_connection_controller.dart';

/// Wireless ADB pairing dialog.
///
/// Two panes only: "Pair a device" (QR code pinned on top, nearby devices
/// scrolling beneath) and "Manual entry". The QR code and the nearby list were
/// separate tabs once; they share a pane because they share a single mDNS scan,
/// and because the code is what most users actually want to see first.
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
    onQrPairingCompleted: _handleQrPairingCompleted,
  );

  var _section = _WirelessDialogSection.pair;
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
    // Synchronous on purpose: the QR code is local computation, so it is on
    // screen in this very first frame rather than after a post-frame callback.
    wirelessController.beginPairing();
  }

  @override
  void dispose() {
    // Required, not optional: the controller owns an unbounded scan loop that
    // would otherwise outlive the dialog. (It was never disposed before.)
    wirelessController.dispose();
    _pairAddressController.dispose();
    _pairingCodeController.dispose();
    _connectAddressController.dispose();
    super.dispose();
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

  /// The scan loop paired a device from a scanned QR code — mirror the outcome
  /// in the dialog the same way an explicit pair would.
  void _handleQrPairingCompleted(WirelessPairResult result) {
    if (!mounted) return;

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
    wirelessController.stopScanning();
    _applySuggestedAddresses();
  }

  void _onSectionChanged(_WirelessDialogSection next) {
    setState(() {
      _section = next;
    });
    if (next == _WirelessDialogSection.pair) {
      wirelessController.beginPairing();
    } else {
      wirelessController.stopScanning();
    }
  }

  void _openManualEntry() {
    setState(() {
      _section = _WirelessDialogSection.manual;
      _showManualConnectSection = true;
    });
    wirelessController.stopScanning();
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

  void _applySuggestedAddresses() {
    final suggestedPairing = wirelessController.suggestedWirelessPairingAddress;
    final suggestedConnect = wirelessController.suggestedWirelessConnectAddress;

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
          _hostFromAddress(suggestedConnect);
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

  // ── Pair pane ──────────────────────────────────────────────────────────

  /// QR code on top, always fully visible; the nearby list scrolls under it.
  ///
  /// In a window too short to hold the code plus a usable list, the pane falls
  /// back to scrolling as a whole rather than clipping.
  ///
  /// The pinned layout depends on this pane getting a bounded height — it comes
  /// from `EaglyDialog(height:)`. Drop that fixed height and the `Expanded`
  /// below has nothing to expand into.
  Widget _buildPairPane(BuildContext context) {
    final qrPanel = WirelessQrPanel(
      payload: wirelessController.qrSession?.payload,
      waiting: wirelessController.isWaitingForQrScan,
      pairing:
          wirelessController.isPairingWireless ||
          wirelessController.isConnectingWireless,
      onRegenerate: wirelessController.regenerateQrCode,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < _minHeightForPinnedQr) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [qrPanel, const Gap(16), _buildNearbySection(context)],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            qrPanel,
            const Gap(16),
            Expanded(
              child: SingleChildScrollView(child: _buildNearbySection(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNearbySection(BuildContext context) {
    final theme = Theme.of(context);
    final targets = _discoveredTargets;
    final selectedTarget = _selectedDiscoveryTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Nearby devices', style: theme.textTheme.titleMedium),
            const Gap(10),
            if (wirelessController.isScanning)
              SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openManualEntry,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Manual entry'),
            ),
          ],
        ),
        const Gap(4),
        Text(
          targets.isEmpty
              ? 'Devices with wireless debugging turned on show up here '
                    'automatically.'
              : 'Already paired with this computer? Pick a device to connect '
                    'without scanning anything.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Gap(12),
        if (targets.isEmpty)
          DelayedReveal(
            delay: const Duration(seconds: 10),
            child: const HintNote(
              title: 'Nothing found yet',
              text:
                  'Turn on Settings → Developer options → Wireless debugging '
                  'on the device and keep that screen open. Some networks '
                  'hide devices from each other; in that case use Manual '
                  'entry with the address the device shows.',
            ),
          )
        else ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final target in targets)
                WirelessDiscoveryCard(
                  target: target,
                  selected: selectedTarget?.host == target.host,
                  onTap: () => _selectDiscoveredTarget(target),
                ),
            ],
          ),
          if (selectedTarget != null) ...[
            const Gap(16),
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
              onPair: selectedTarget.pairingService == null
                  ? null
                  : _handlePair,
              onConnect: selectedTarget.canConnect ? _handleConnect : null,
              onUseManualEntry: _openManualEntry,
            ),
          ],
        ],
      ],
    );
  }

  // ── Manual pane ────────────────────────────────────────────────────────

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
    return AnimatedBuilder(
      animation: Listenable.merge([manager, wirelessController]),
      builder: (context, _) {
        return EaglyDialog(
          title: 'Wireless ADB',
          icon: Icons.wifi_tethering,
          width: 720,
          height: 580,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<_WirelessDialogSection>(
                segments: const [
                  ButtonSegment<_WirelessDialogSection>(
                    value: _WirelessDialogSection.pair,
                    icon: Icon(Icons.wifi_tethering),
                    label: Text('Pair a device'),
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
              const Gap(14),
              WirelessFeedbackBanner(
                message: wirelessController.wirelessMessage,
                error: wirelessController.wirelessError,
              ),
              if (wirelessController.wirelessMessage != null ||
                  wirelessController.wirelessError != null)
                const Gap(14),
              Flexible(
                child: switch (_section) {
                  _WirelessDialogSection.pair => _buildPairPane(context),
                  _WirelessDialogSection.manual => SingleChildScrollView(
                    child: _buildManualEntryTab(context),
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _WirelessDialogSection { pair, manual }

/// Below this the QR card plus a usable device list no longer fit, so the pair
/// pane scrolls as a whole instead of pinning the code.
const double _minHeightForPinnedQr = 340;
