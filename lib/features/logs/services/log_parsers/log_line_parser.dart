import 'dart:async';

import '../../data/models/log_entry.dart';

/// Turns a device log tool's output, one line at a time, into [LogEntry]s.
///
/// Both platforms' tools can spread one entry over several lines, and neither
/// marks where an entry ends — only the start of the next one shows that. So a
/// parser buffers the entry being built: [addLine] yields the entries a line
/// completes (the previous one, when a new one starts), and [flush] hands over
/// the one still being built.
///
/// Drive a parser with [parseLogLines] rather than by hand; it also flushes
/// when the stream goes quiet, which a parser can't do on its own.
abstract interface class LogLineParser {
  Iterable<LogEntry> addLine(String line);

  /// Returns the entry being built, if any, and forgets it.
  LogEntry? flush();
}

/// How long a log stream may stay silent before the entry the parser is
/// holding is emitted anyway. The tools write a whole entry in one go, so in
/// practice a gap this long only ever falls between entries.
const Duration logLineIdleFlushInterval = Duration(milliseconds: 100);

/// Parses [lines] with [parser], flushing the entry it holds when [lines]
/// ends or goes quiet for [idleFlushInterval] (without that, the last entry of
/// a burst would wait for the next line, which may be a long time coming).
///
/// Errors on [lines] are forwarded unchanged.
Stream<LogEntry> parseLogLines(
  Stream<String> lines,
  LogLineParser parser, {
  Duration idleFlushInterval = logLineIdleFlushInterval,
}) {
  late final StreamController<LogEntry> controller;
  StreamSubscription<String>? subscription;
  Timer? idleFlushTimer;
  var sawLineSinceTick = false;

  void emitPending() {
    final pending = parser.flush();
    if (pending != null) controller.add(pending);
  }

  controller = StreamController<LogEntry>(
    onListen: () {
      idleFlushTimer = Timer.periodic(idleFlushInterval, (_) {
        if (sawLineSinceTick) {
          sawLineSinceTick = false;
          return;
        }
        emitPending();
      });
      subscription = lines.listen(
        (line) {
          sawLineSinceTick = true;
          parser.addLine(line).forEach(controller.add);
        },
        onError: controller.addError,
        onDone: () {
          idleFlushTimer?.cancel();
          emitPending();
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      idleFlushTimer?.cancel();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
