import 'dart:io';

/// Where one Inspektor server listens on a device.
///
/// On Android that is an abstract Unix socket named
/// `inspektor_<pid>_<runtime>`; see Inspektor's docs/REMOTE_PROTOCOL.md.
/// Two endpoints are the same when their [name]s are: a restarted app gets a
/// new pid, so a new name and a new endpoint.
class const InspektorEndpoint({
  /// The socket's name without the leading `@`, as `adb forward
  /// localabstract:` wants it.
  required final String name,
  final int? pid,

  /// `kotlin` or `dart`.
  final String? runtime,
}) {
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
