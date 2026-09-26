import 'dart:async';

import '../../data/models/log_entry.dart';

/// Turns a device log tool's output, one line at a time, into [LogEntry]s.
///
/// Both platforms' tools can spread one entry over several lines, and neither
/// marks where an entry ends — only the start of the next one shows that. So a
/// parser buffers the entry being built: [addLine] returns the entries a line
/// completes (the previous one, when a new one starts), and [flush] hands over
/// the one still being built.
///
/// Drive a parser with [parseLogLines] (a tool's line-by-line output) or
/// [parseLogRecords] (a source that frames whole entries) rather than by hand.
abstract interface class LogLineParser {
  /// Feeds one line and returns the entries it completes, oldest first — most
  /// often none. Eager rather than a lazy `sync*` iterable, so a caller that
  /// ignores the result still has the line consumed.
  List<LogEntry> addLine(String line);

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

/// Parses [records] with [parser], where each record is one complete entry
/// that may span several lines — the iOS syslog relay frames its messages
/// this way. The record boundary is a known end of entry, so the entry is
/// flushed straight away: no idle timer, no latency, and nothing for a late
/// line to be cut off from.
///
/// A parser exception is delivered as an error event on the returned stream.
Stream<LogEntry> parseLogRecords(Stream<String> records, LogLineParser parser) {
  return records.expand((record) {
    final lines = record.split('\n');
    // A record that ends in its own newline would otherwise add an empty line.
    if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();

    final entries = <LogEntry>[];
    for (final line in lines) {
      entries.addAll(parser.addLine(line));
    }
    final entry = parser.flush();
    if (entry != null) entries.add(entry);
    return entries;
  });
}
