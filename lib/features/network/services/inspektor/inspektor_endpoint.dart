import 'dart:io';

/// Where one Inspektor server listens on a device; see Inspektor's
/// docs/REMOTE_PROTOCOL.md.
///
/// On Android that is an abstract Unix socket named
/// `inspektor_<pid>_<runtime>`, and a restarted app gets a new pid, so a new
/// name and a new endpoint. On iOS it is a loopback [port], which a restarted
/// app usually takes again. Two endpoints are the same when their [name]s
/// are.
class const InspektorEndpoint({
  /// Android: the socket's name without the leading `@`, as adb's
  /// `localabstract:` forwards take it. iOS: `tcp:<port>`.
  required final String name,
  final int? pid,

  /// `kotlin` or `dart`.
  final String? runtime,

  /// The device-side TCP port, on iOS.
  final int? port,
}) {
  /// The server listening on [port] of an iOS device.
  InspektorEndpoint.tcp(int port) : this(name: 'tcp:$port', port: port);

  @override
  bool operator ==(Object other) =>
      other is InspektorEndpoint && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'InspektorEndpoint($name)';
}

/// A host-side way into an [InspektorEndpoint]: a local port that a tunnel
/// (`adb forward`, usbmux) connects through to the device. [close] tears the
/// tunnel down.
class const InspektorTunnel({
  required final InternetAddress host,
  required final int port,
  required final Future<void> Function() close,
});

/// The ports an Inspektor server takes on iOS and desktop: the first free one
/// from [inspektorFirstPort], so one per app running at once.
final List<int> inspektorPorts = List.unmodifiable([
  for (var port = inspektorFirstPort; port < inspektorFirstPort + 8; port++)
    port,
]);

/// Matches Inspektor's `REMOTE_FIRST_PORT`.
const int inspektorFirstPort = 38470;

/// What every Inspektor abstract socket's path starts with in
/// `/proc/net/unix`.
const String inspektorSocketMarker = '@inspektor_';

final RegExp _socketPath = RegExp(r'^@(inspektor_(\d+)_([a-z]+))$');

/// The Inspektor endpoints in a `/proc/net/unix` dump (or the lines of it
/// that mention [inspektorSocketMarker]).
///
/// The path is the last column. A listening socket and every connection
/// accepted from it carry the same path, so each name is returned once, in
/// the order first seen. Lines that are not Inspektor sockets are skipped.
List<InspektorEndpoint> parseInspektorSockets(String procNetUnix) {
  final seen = <String>{};
  final endpoints = <InspektorEndpoint>[];
  for (final line in procNetUnix.split('\n')) {
    final columns = line.trim().split(RegExp(r'\s+'));
    if (columns.isEmpty) continue;
    final match = _socketPath.firstMatch(columns.last);
    if (match == null) continue;
    final name = match.group(1)!;
    if (!seen.add(name)) continue;
    endpoints.add(
      InspektorEndpoint(
        name: name,
        pid: int.tryParse(match.group(2)!),
        runtime: match.group(3),
      ),
    );
  }
  return endpoints;
}
