import '../../src/rust/api/ios_network.dart' as rust;
import 'ios_network_service.dart';

/// [IosNetworkService] backed by usbmuxd `Connect` requests through the
/// `idevice` crate; the forward is Eagly's own `iproxy`.
class RustIosNetworkService implements IosNetworkService {
  @override
  Future<List<int>> probePorts(String deviceId, List<int> ports) async =>
      await rust.probeIosPorts(udid: deviceId, ports: ports);

  @override
  Future<int> forwardPort(String deviceId, int devicePort) =>
      rust.startIosPortForward(udid: deviceId, devicePort: devicePort);

  @override
  Future<void> removeForward(int hostPort) =>
      rust.stopIosPortForward(hostPort: hostPort);
}
