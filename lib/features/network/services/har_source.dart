import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../utils/utils.dart';
import '../data/har.dart';
import '../data/network_transaction.dart';
import 'network_source.dart';

/// A HAR file opened in the Network pane. It delivers every entry at once and
/// then ends; bodies come from the file itself.
class HarSource(@override final String label, List<HarEntry> entries)
    implements NetworkSource {
  this
    : _bodies = {
        for (final entry in entries) entry.transaction.id: entry.bodies,
      } {
    for (final entry in entries) {
      _events.add(NetworkTransactionUpserted(entry.transaction));
    }
    _events
      ..add(
        NetworkSourceStatusChanged(
          NetworkSourceStatus.ended,
          message: '${entries.length} requests from $label',
        ),
      )
      ..close();
  }

  /// Reads and decodes the HAR at [path]. Decoding runs on another isolate:
  /// a capture with bodies is easily tens of megabytes. Throws a
  /// [FormatException] for a file that is not a HAR, or a
  /// [FileSystemException] when it cannot be read.
  static Future<HarSource> open(String path) async {
    final text = await readTextLenient(File(path));
    final entries = await Isolate.run(() => decodeHar(text));
    return HarSource(extractFileName(path), entries);
  }

  final Map<String, Map<NetworkBodyPart, NetworkBody>> _bodies;
  final StreamController<NetworkSourceEvent> _events =
      StreamController<NetworkSourceEvent>();

  @override
  NetworkSourceKind get kind => NetworkSourceKind.har;

  @override
  Stream<NetworkSourceEvent> get events => _events.stream;

  @override
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part) async {
    final body = _bodies[transactionId]?[part];
    if (body == null) {
      throw StateError(
        'The file has no ${part.wireName} body for this request.',
      );
    }
    return body;
  }

  @override
  Future<void> dispose() async => _bodies.clear();
}
