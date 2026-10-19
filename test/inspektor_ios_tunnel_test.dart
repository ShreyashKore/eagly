import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/ios/ios_network_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone whose [open] ports accept connections, recording every probe and
/// forward.
class _FakeIosNetworkService implements IosNetworkService {
  Set<int> open = {};
  final List<List<int>> probes = [];
  final Map<int, int> forwards = {};
  final List<int> removed = [];
  int _nextHostPort = 50000;

  @override
  Future<List<int>> probePorts(String deviceId, List<int> ports) async {
    probes.add(ports);
    return [
      for (final port in ports)
        if (open.contains(port)) port,
    ];
  }

  @override
  Future<int> forwardPort(String deviceId, int devicePort) async {
    final hostPort = _nextHostPort++;
    forwards[hostPort] = devicePort;
    return hostPort;
  }

  @override
  Future<void> removeForward(int hostPort) async => removed.add(hostPort);
}

void main() {
  late _FakeIosNetworkService network;
  late DeviceSessionRepository repository;

  setUp(() {
    network = _FakeIosNetworkService();
    repository = DeviceSessionRepository(
      device: const IosDevice('00008140-0001', 'device'),
      iosNetworkService: network,
    );
  });

  test('finds the Inspektor ports that accept a connection', () async {
    network.open = {38471, 38470, 9000};

    final endpoints = await repository.findInspektorEndpoints();

    expect(endpoints, [
      InspektorEndpoint.tcp(38470),
      InspektorEndpoint.tcp(38471),
    ]);
    expect(network.probes.single, inspektorPorts);
  });

  test('a tunnelled port is reported without being probed, until its tunnel '
      'closes', () async {
    network.open = {38470};
    final tunnel = await repository.openInspektorTunnel(
      InspektorEndpoint.tcp(38470),
    );
    expect(network.forwards[tunnel.port], 38470);

    expect(await repository.findInspektorEndpoints(), [
      InspektorEndpoint.tcp(38470),
    ]);
    expect(network.probes.last, isNot(contains(38470)));

    await tunnel.close();
    expect(network.removed, [tunnel.port]);

    network.open = {};
    expect(await repository.findInspektorEndpoints(), isEmpty);
    expect(network.probes.last, contains(38470));
  });
}
