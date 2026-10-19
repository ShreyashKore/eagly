import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:eagly/features/network/services/inspektor/inspektor_frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decodes [chunks] as one connection's bytes; returns the frames and the
/// error that ended the stream, if any.
Future<(List<Map<String, Object?>>, Object?)> decode(
  List<List<int>> chunks,
) async {
  final frames = <Map<String, Object?>>[];
  Object? failure;
  final done = Completer<void>();
  Stream<List<int>>.fromIterable(chunks)
      .transform(const InspektorFrameDecoder())
      .listen(
        frames.add,
        onError: (Object error) => failure ??= error,
        onDone: done.complete,
      );
  await done.future;
  return (frames, failure);
}

Uint8List frameWithLength(int length, List<int> payload) {
  final header = ByteData(4)..setUint32(0, length);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);
}

void main() {
  test('a frame is a big-endian length and UTF-8 JSON', () {
    final frame = encodeInspektorFrame({'type': 'hello', 'name': 'é'});
    final payload = utf8.encode('{"type":"hello","name":"é"}');
    expect(ByteData.sublistView(frame).getUint32(0), payload.length);
    expect(frame.sublist(4), payload);
  });

  test(
    'frames survive any chunking, byte by byte or several at once',
    () async {
      final bytes = [
        ...encodeInspektorFrame({'n': 1}),
        ...encodeInspektorFrame({'n': 2, 'text': 'x' * 300}),
        ...encodeInspektorFrame({'n': 3}),
      ];

      final (byByte, byteError) = await decode([
        for (final byte in bytes) [byte],
      ]);
      final (together, togetherError) = await decode([bytes]);

      expect(byteError, isNull);
      expect(togetherError, isNull);
      expect([for (final frame in byByte) frame['n']], [1, 2, 3]);
      expect([for (final frame in together) frame['n']], [1, 2, 3]);
    },
  );

  group('the connection ends on the first bad frame', () {
    test('when the length is over the cap', () async {
      final (frames, error) = await decode([
        encodeInspektorFrame({'n': 1}),
        frameWithLength(inspektorMaxFrameBytes + 1, const []),
        encodeInspektorFrame({'n': 2}),
      ]);
      expect([for (final frame in frames) frame['n']], [1]);
      expect(error, isA<InspektorProtocolException>());
    });

    // The rule that keeps a web page out (docs/NETWORK_INSPECTOR.md §4.3):
    // the only bytes a browser can put on the socket are an HTTP request,
    // and its first four bytes read as a length over a gigabyte.
    for (final method in ['GET ', 'POST', 'PUT ', 'OPTI']) {
      test('when a browser sends an HTTP request ($method…)', () async {
        final (frames, error) = await decode([
          utf8.encode(
            '$method/ HTTP/1.1\r\nHost: 127.0.0.1:38470\r\n\r\n'
            '{"id":1,"method":"overrides.put"}',
          ),
        ]);
        expect(frames, isEmpty);
        expect(error, isA<InspektorProtocolException>());
      });
    }

    test('when the payload is not JSON', () async {
      final (frames, error) = await decode([
        frameWithLength(5, utf8.encode('hello')),
      ]);
      expect(frames, isEmpty);
      expect(error, isA<InspektorProtocolException>());
    });

    test('when the payload is not UTF-8', () async {
      final (_, error) = await decode([
        frameWithLength(2, const [0xC3, 0x28]),
      ]);
      expect(error, isA<InspektorProtocolException>());
    });

    test('when the payload is JSON but not an object', () async {
      final (_, error) = await decode([
        frameWithLength(7, utf8.encode('[1,2,3]')),
      ]);
      expect(error, isA<InspektorProtocolException>());
    });

    test('when the frame is empty', () async {
      final (_, error) = await decode([frameWithLength(0, const [])]);
      expect(error, isA<InspektorProtocolException>());
    });
  });

  test('a connection that closes inside a frame reports it', () async {
    final frame = encodeInspektorFrame({'n': 1});
    final (frames, error) = await decode([frame.sublist(0, frame.length - 2)]);
    expect(frames, isEmpty);
    expect(error, isA<InspektorProtocolException>());
  });

  test('the encoder refuses a message over the cap', () {
    expect(
      () => encodeInspektorFrame({'body': 'x' * inspektorMaxFrameBytes}),
      throwsArgumentError,
    );
  });
}
