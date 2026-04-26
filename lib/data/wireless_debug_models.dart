enum WirelessDebugServiceType { connect, pairing, unknown }

class WirelessDebugService {
  const WirelessDebugService({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
  });

  final String name;
  final WirelessDebugServiceType type;
  final String host;
  final int port;

  String get address => '$host:$port';

  String get typeLabel => switch (type) {
    WirelessDebugServiceType.connect => 'Connect',
    WirelessDebugServiceType.pairing => 'Pairing',
    WirelessDebugServiceType.unknown => 'Unknown',
  };
}

class WirelessServiceDiscoveryResult {
  const WirelessServiceDiscoveryResult({this.services = const [], this.error});

  final List<WirelessDebugService> services;
  final String? error;

  bool get isSuccess => error == null;

  factory WirelessServiceDiscoveryResult.success({
    required List<WirelessDebugService> services,
  }) {
    return WirelessServiceDiscoveryResult(services: services);
  }

  factory WirelessServiceDiscoveryResult.failure({required String error}) {
    return WirelessServiceDiscoveryResult(error: error);
  }
}

class DeviceCommandResult {
  const DeviceCommandResult({this.message, this.error});

  final String? message;
  final String? error;

  bool get isSuccess => error == null;

  factory DeviceCommandResult.success({required String message}) {
    return DeviceCommandResult(message: message);
  }

  factory DeviceCommandResult.failure({required String error}) {
    return DeviceCommandResult(error: error);
  }
}
