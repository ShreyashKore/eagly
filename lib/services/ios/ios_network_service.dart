import 'ios_backend.dart';
import 'rust_ios_network_service.dart';

/// TCP ports on an iOS device, reached through usbmuxd: how the Network pane
/// finds an app serving its traffic with Inspektor, and connects to it.
///
/// Rust only. The libimobiledevice backend has no way to probe a port, and
/// `iproxy` is not bundled, so with the CLIs the device simply has no ports.
abstract interface class IosNetworkService {
  /// Which of [ports] accept a connection on the device right now. A probe
  /// that connects hangs up at once.
  Future<List<int>> probePorts(String deviceId, List<int> ports);

  /// Forwards a free loopback port on this computer to [devicePort] on the
  /// device, and returns it. It stays open until [removeForward].
  Future<int> forwardPort(String deviceId, int devicePort);

  /// Closes the forward on [hostPort] and every connection through it.
  Future<void> removeForward(int hostPort);
}

IosNetworkService createIosNetworkService() =>
    useRustIosBackend ? RustIosNetworkService() : const _NoIosNetworkService();

/// The CLI backend's answer: no ports, and nothing to forward to.
class const _NoIosNetworkService() implements IosNetworkService {
  @override
  Future<List<int>> probePorts(String deviceId, List<int> ports) async =>
      const [];

  @override
  Future<int> forwardPort(String deviceId, int devicePort) =>
      throw UnsupportedError('Forwarding iOS ports needs the Rust backend.');

  @override
  Future<void> removeForward(int hostPort) async {}
}
