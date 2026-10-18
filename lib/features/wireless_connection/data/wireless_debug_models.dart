enum WirelessDebugServiceType { connect, pairing, unknown }

class const WirelessDebugService({
  required final String name,
  required final WirelessDebugServiceType type,
  required final String host,
  required final int port,
}) {
  String get address => '$host:$port';

  String get typeLabel => switch (type) {
    WirelessDebugServiceType.connect => 'Connect',
    WirelessDebugServiceType.pairing => 'Pairing',
    WirelessDebugServiceType.unknown => 'Unknown',
  };
}

class const WirelessServiceDiscoveryResult({
  final List<WirelessDebugService> services = const [],
  final String? error,
}) {
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

class const DeviceCommandResult({final String? message, final String? error}) {
  bool get isSuccess => error == null;

  factory DeviceCommandResult.success({required String message}) {
    return DeviceCommandResult(message: message);
  }

  factory DeviceCommandResult.failure({required String error}) {
    return DeviceCommandResult(error: error);
  }
}
