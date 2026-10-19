import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The largest frame either side of the Inspektor protocol accepts. Bodies
/// larger than this are read in ranges.
const int inspektorMaxFrameBytes = 16 * 1024 * 1024;

/// A peer broke the Inspektor protocol: an oversized or malformed frame, an
/// unexpected message. The connection is not usable afterwards.
class InspektorProtocolException(final String message) implements Exception {
  @override
  String toString() => 'InspektorProtocolException: $message';
}

/// Encodes [message] as one frame: a 4-byte big-endian length, then that many
/// bytes of UTF-8 JSON (docs/NETWORK_INSPECTOR.md §4.4).
Uint8List encodeInspektorFrame(Map<String, Object?> message) {
  final payload = utf8.encode(jsonEncode(message));
  if (payload.length > inspektorMaxFrameBytes) {
    throw ArgumentError.value(
      payload.length,
      'message',
      'encodes to more than $inspektorMaxFrameBytes bytes',
    );
  }
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Splits a byte stream into Inspektor frames and decodes each into its JSON
/// object.
///
/// Chunk boundaries are irrelevant: a frame may arrive a byte at a time, or
/// several in one chunk. Each payload is read into a buffer sized from its
/// header, so a 16 MiB body costs one allocation and no re-copying.
///
/// The first frame that is longer than [inspektorMaxFrameBytes], is not UTF-8
/// or is not a JSON object ends the stream with an [InspektorProtocolException]
/// and everything after it is ignored. That rule is what keeps a web page from
/// using the socket: the HTTP request a browser can send starts with text
/// (`GET `, `POST`) that reads as a length over a gigabyte (§4.3). The owner of
/// the connection closes it on that error.
///
/// Apply it with [bind], not `socket.transform(…)`: a `Socket` is a
/// `Stream<Uint8List>`, and `transform` checks the decoder against that
/// runtime type and throws.
class const InspektorFrameDecoder()
    extends StreamTransformerBase<List<int>, Map<String, Object?>> {
  @override
  Stream<Map<String, Object?>> bind(Stream<List<int>> stream) =>
      Stream<Map<String, Object?>>.eventTransformed(stream, _FrameSink.new);
}

class _FrameSink(final EventSink<Map<String, Object?>> _out)
    implements EventSink<List<int>> {
  final Uint8List _header = Uint8List(4);
  int _headerFilled = 0;
  Uint8List? _payload;
  int _payloadFilled = 0;
  bool _failed = false;

  @override
  void add(List<int> chunk) {
    var offset = 0;
    while (!_failed && offset < chunk.length) {
      final payload = _payload;
      if (payload == null) {
        final take = math.min(4 - _headerFilled, chunk.length - offset);
        _header.setRange(_headerFilled, _headerFilled + take, chunk, offset);
        _headerFilled += take;
        offset += take;
        if (_headerFilled < 4) return;
        _headerFilled = 0;
        final length = ByteData.sublistView(_header).getUint32(0);
        if (length > inspektorMaxFrameBytes) {
          _fail(
            'A frame announced $length bytes; the limit is '
            '$inspektorMaxFrameBytes.',
          );
          return;
        }
        _payload = Uint8List(length);
        _payloadFilled = 0;
        if (length == 0) _finishPayload();
      } else {
        final take = math.min(
          payload.length - _payloadFilled,
          chunk.length - offset,
        );
        payload.setRange(_payloadFilled, _payloadFilled + take, chunk, offset);
        _payloadFilled += take;
        offset += take;
        if (_payloadFilled == payload.length) _finishPayload();
      }
    }
  }

  void _finishPayload() {
    final payload = _payload!;
    _payload = null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      _fail('A frame was not UTF-8 JSON.');
      return;
    }
    if (decoded is! Map<String, Object?>) {
      _fail('A frame was not a JSON object.');
      return;
    }
    _out.add(decoded);
  }

  void _fail(String message) {
    _failed = true;
    _payload = null;
    _out
      ..addError(InspektorProtocolException(message))
      ..close();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_failed) return;
    _out.addError(error, stackTrace);
  }

  @override
  void close() {
    if (_failed) return;
    if (_payload != null || _headerFilled > 0) {
      _out.addError(
        InspektorProtocolException('The connection closed inside a frame.'),
      );
    }
    _out.close();
  }
}
