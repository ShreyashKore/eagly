import 'dart:async';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/network/services/inspektor/inspektor_token.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = '0123456789abcdef0123456789abcdef';
const _other = 'fedcba9876543210fedcba9876543210';

LogEntry _line(String message, {String pid = '4242'}) => LogEntry(
  timestamp: 'Oct 25 11:00:00',
  pid: pid,
  tid: '',
  level: 'Notice',
  tag: 'Example',
  message: message,
);

String _announce(int port, String token) =>
    'Inspektor: remote inspection listening on 127.0.0.1:$port, token $token';

void main() {
  late StreamController<LogEntry> log;
  late InspektorTokenListener listener;

  setUp(() {
    log = StreamController<LogEntry>();
    listener = InspektorTokenListener(log.stream, port: 38470);
  });

  tearDown(() => listener.close());

  test('parses the line the server writes, and nothing else', () {
    expect(parseInspektorTokenLine(_announce(38471, _token)), (
      port: 38471,
      token: _token,
    ));
    expect(
      parseInspektorTokenLine(
        'Inspektor: remote inspection listening on @inspektor_1_kotlin',
      ),
      isNull,
    );
    expect(parseInspektorTokenLine('token $_token'), isNull);
  });

  test('started completes on the first entry of any kind', () async {
    var started = false;
    unawaited(listener.started.then((_) => started = true));
    await pumpEventQueue();
    expect(started, isFalse);

    log.add(_line('unrelated'));
    await pumpEventQueue();
    expect(started, isTrue);
  });

  test('waits for the line of its port and the hello\'s pid', () async {
    final token = listener.tokenFor(4242);

    log
      ..add(_line(_announce(38471, _other)))
      ..add(_line(_announce(38470, _other), pid: '9999'))
      ..add(_line(_announce(38470, _token)));

    expect(await token, _token);
  });

  test('answers at once with a line already seen, latest first', () async {
    log
      ..add(_line(_announce(38470, _other)))
      ..add(_line(_announce(38470, _token)));
    await pumpEventQueue();

    expect(await listener.tokenFor(4242), _token);
    expect(await listener.tokenFor(null), _token);
  });

  test('a line without a pid counts for any pid', () async {
    final token = listener.tokenFor(4242);
    log.add(_line(_announce(38470, _token), pid: ''));
    expect(await token, _token);
  });

  test('closing fails a pending wait and stops reading', () async {
    final token = listener.tokenFor(4242);
    await listener.close();

    await expectLater(token, throwsStateError);
    expect(log.hasListener, isFalse);
  });

  test('the log ending fails a pending wait', () async {
    final token = listener.tokenFor(4242);
    await log.close();

    await expectLater(
      token,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ended'),
        ),
      ),
    );
  });
}
