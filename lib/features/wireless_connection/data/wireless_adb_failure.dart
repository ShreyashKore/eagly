import 'dart:io';

/// What a wireless adb command was trying to do when it failed.
enum WirelessAdbAction { pair, connect }

/// Why a wireless pair or connect failed, in terms a user can act on.
enum WirelessAdbFailureKind {
  /// Eagly reached the device, the adb server did not: the server is not
  /// allowed on the local network (macOS) — restarting it from Eagly fixes it.
  adbServerBlocked,

  /// Neither Eagly nor adb can reach the device's address.
  networkUnreachable,

  /// The device answered but nothing listens on that port.
  portClosed,

  /// The device never answered.
  noAnswer,

  /// The device refused the pairing code.
  pairingRejected,

  /// Reached the device, but it has not paired with this computer.
  notPaired,
}

/// Whether Eagly's own process could open a TCP connection to an address.
///
/// Compared with adb's answer for the same address, this tells a blocked adb
/// server apart from a device that is genuinely out of reach.
enum WirelessReachability { reachable, unreachable, refused, timedOut, unknown }

/// A wireless adb failure explained for the user, with the raw adb output kept
/// for reference.
class const WirelessAdbFailure({
  required final WirelessAdbFailureKind kind,
  required final String title,
  required final String explanation,
  required final String rawError,

  /// Restarting the adb server from Eagly is likely to help.
  final bool suggestsAdbRestart = false,

  /// Eagly's Local Network permission (macOS) may be what blocks it.
  final bool suggestsLocalNetworkSettings = false,
}) {
  /// One line for a snack bar.
  String get summary => '$title $explanation';
}

/// The macOS System Settings pane that lists apps allowed on the local network.
const localNetworkSettingsUrl =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork';

/// The adb failure modes we recognise in `adb pair` / `adb connect` output.
enum _AdbErrorSignal {
  noRoute,
  refused,
  timedOut,
  wrongCode,
  pairingClient,
  auth,
}

_AdbErrorSignal? _readAdbError(String error) {
  final text = error.toLowerCase();
  bool has(Iterable<String> needles) => needles.any(text.contains);

  if (has(['wrong password'])) return _AdbErrorSignal.wrongCode;
  if (has(['failed to authenticate', 'unauthorized'])) {
    return _AdbErrorSignal.auth;
  }
  if (has([
    'no route to host',
    'network is unreachable',
    'host is down',
    '(10065)', // Windows WSAEHOSTUNREACH
    '(10051)', // Windows WSAENETUNREACH
  ])) {
    return _AdbErrorSignal.noRoute;
  }
  if (has(['connection refused', 'actively refused', '(10061)'])) {
    return _AdbErrorSignal.refused;
  }
  if (has(['timed out', 'did not properly respond', '(10060)'])) {
    return _AdbErrorSignal.timedOut;
  }
  // `adb pair` reports an unreachable pairing port this vaguely.
  if (has(['unable to start pairing client', 'protocol fault'])) {
    return _AdbErrorSignal.pairingClient;
  }
  return null;
}

/// Whether [error] is the kind of failure Eagly should double-check by trying
/// the address itself before explaining it.
bool wirelessAdbErrorNeedsProbe(String error) => switch (_readAdbError(error)) {
  _AdbErrorSignal.noRoute ||
  _AdbErrorSignal.timedOut ||
  _AdbErrorSignal.pairingClient => true,
  _ => false,
};

/// Turns raw adb output for a failed wireless [action] on [address] into an
/// explanation, or `null` when the output matches nothing we recognise.
///
/// [reachability] is Eagly's own attempt at the same address; it is what
/// separates "the adb server is blocked" from "the device is out of reach".
WirelessAdbFailure? diagnoseWirelessAdbFailure({
  required String error,
  required String address,
  required WirelessAdbAction action,
  WirelessReachability reachability = WirelessReachability.unknown,
  bool? isMacOS,
}) {
  final macOS = isMacOS ?? Platform.isMacOS;
  final signal = _readAdbError(error);
  if (signal == null) return null;

  final host = _hostOf(address);
  final port = _portOf(address);
  final where = action == WirelessAdbAction.pair
      ? 'Pair device with pairing code'
      : 'Wireless debugging';

  // Eagly got through where adb did not: the device is fine, the adb server
  // is the problem. On macOS that is the Local Network permission, which
  // belongs to whichever app started the server.
  if (reachability == WirelessReachability.reachable &&
      (signal == _AdbErrorSignal.noRoute ||
          signal == _AdbErrorSignal.pairingClient)) {
    return WirelessAdbFailure(
      kind: WirelessAdbFailureKind.adbServerBlocked,
      title: 'The adb server can\'t reach your network.',
      explanation: macOS
          ? 'Eagly can reach $host, but the running adb server can\'t. It was '
                'probably started by another app that macOS doesn\'t allow on '
                'the local network. Restart adb so Eagly starts it instead.'
          : 'Eagly can reach $host, but the running adb server can\'t. '
                'Restart adb and try again.',
      rawError: error,
      suggestsAdbRestart: true,
    );
  }

  switch (signal) {
    case _AdbErrorSignal.wrongCode:
      return WirelessAdbFailure(
        kind: WirelessAdbFailureKind.pairingRejected,
        title: 'The device rejected the pairing code.',
        explanation:
            'The code was wrong or the pairing screen closed. On the device '
            'open "$where" again and use the new code and address it shows.',
        rawError: error,
      );
    case _AdbErrorSignal.auth:
      return WirelessAdbFailure(
        kind: WirelessAdbFailureKind.notPaired,
        title: 'This computer isn\'t paired with the device.',
        explanation:
            'Pair it first: on the device open Wireless debugging → "Pair '
            'device with pairing code" (or scan the QR code), then connect.',
        rawError: error,
      );
    case _AdbErrorSignal.refused:
      return WirelessAdbFailure(
        kind: WirelessAdbFailureKind.portClosed,
        title: 'Nothing is listening on port ${port ?? '?'}.',
        explanation: action == WirelessAdbAction.pair
            ? 'The pairing screen may have closed. On the device open "$where" '
                  'again; it shows a new address and code each time.'
            : 'Wireless debugging is off, or its port changed — it changes '
                  'every time Wireless debugging is turned on. Check "IP '
                  'address & port" on the device\'s Wireless debugging screen.',
        rawError: error,
      );
    case _AdbErrorSignal.noRoute || _AdbErrorSignal.pairingClient
        when reachability == WirelessReachability.refused:
      return diagnoseWirelessAdbFailure(
        error: 'Connection refused',
        address: address,
        action: action,
        isMacOS: macOS,
      )?.copyWithRaw(error);
    case _AdbErrorSignal.noRoute:
      return WirelessAdbFailure(
        kind: WirelessAdbFailureKind.networkUnreachable,
        title: 'This computer can\'t reach $host.',
        explanation: macOS
            ? 'Check the device is on the same Wi-Fi as this computer. If it '
                  'is, macOS may be blocking local network access: allow Eagly '
                  'under System Settings → Privacy & Security → Local Network, '
                  'then restart adb.'
            : 'Check the device is on the same Wi-Fi as this computer, and that '
                  'the network lets devices talk to each other (guest Wi-Fi '
                  'often doesn\'t).',
        rawError: error,
        suggestsAdbRestart: true,
        suggestsLocalNetworkSettings: macOS,
      );
    case _AdbErrorSignal.timedOut || _AdbErrorSignal.pairingClient:
      return WirelessAdbFailure(
        kind: WirelessAdbFailureKind.noAnswer,
        title: '$host didn\'t answer.',
        explanation:
            'Wake the device and keep its $where screen open. Make sure it is '
            'on the same Wi-Fi as this computer; guest and public networks '
            'often stop devices from talking to each other.',
        rawError: error,
      );
  }
}

extension on WirelessAdbFailure {
  WirelessAdbFailure copyWithRaw(String rawError) => WirelessAdbFailure(
    kind: kind,
    title: title,
    explanation: explanation,
    rawError: rawError,
    suggestsAdbRestart: suggestsAdbRestart,
    suggestsLocalNetworkSettings: suggestsLocalNetworkSettings,
  );
}

/// Tries a TCP connection to [address] from Eagly's own process.
///
/// On macOS the first attempt also makes the system ask whether Eagly may use
/// the local network, which is the permission a server Eagly starts inherits.
Future<WirelessReachability> probeWirelessAddress(
  String address, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final host = _hostOf(address);
  final port = _portOf(address);
  if (host == null || port == null) return WirelessReachability.unknown;

  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return WirelessReachability.reachable;
  } on SocketException catch (error) {
    final message = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    final code = error.osError?.errorCode;
    if (message.contains('refused') || code == 61 || code == 111) {
      return WirelessReachability.refused;
    }
    if (message.contains('no route') ||
        message.contains('unreachable') ||
        message.contains('host is down') ||
        code == 65 ||
        code == 113 ||
        code == 51 ||
        code == 101) {
      return WirelessReachability.unreachable;
    }
    if (message.contains('timed out')) return WirelessReachability.timedOut;
    return WirelessReachability.unknown;
  } catch (_) {
    return WirelessReachability.unknown;
  }
}

String? _hostOf(String address) {
  final index = address.trim().lastIndexOf(':');
  return index <= 0 ? null : address.trim().substring(0, index);
}

int? _portOf(String address) {
  final index = address.trim().lastIndexOf(':');
  return index <= 0 ? null : int.tryParse(address.trim().substring(index + 1));
}
