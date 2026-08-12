import 'package:collection/collection.dart';

import '../data/wireless_debug_models.dart';

/// A wireless ADB device discovered via mDNS, grouping the pairing service and
/// any connect services advertised for the same host.
class DiscoveredWirelessTarget {
  const DiscoveredWirelessTarget({
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
