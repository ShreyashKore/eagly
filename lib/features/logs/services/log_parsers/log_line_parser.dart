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
/// A flush can come too early — an idle flush while the tool is mid-write —
/// so a parser must never drop the lines that follow one: body lines arriving
/// after a [flush], before any new header, start a new entry under the flushed
/// entry's header. The worst case is one message split across two rows, never
/// lost text. Lines before the first header ever seen may be ignored.
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

  /// What the parser is holding, which decides how soon an idle stream may
  /// [flush] it.
  PendingEntryStatus get pendingEntryStatus;
}

/// What a [LogLineParser] is holding, as far as flushing it early goes.
enum PendingEntryStatus {
  /// Nothing is buffered.
  none,

  /// A header whose body hasn't arrived yet. There is nothing to show, and
  /// holding it delays nothing — the next line either fills it or starts a new
  /// entry — so it is never flushed for being idle; end of stream flushes it.
  awaitingBody,

  /// The entry hasn't ended the way a whole entry does, so the tool may still
  /// be writing it. Flushed only after [logLineIncompleteEntryFlushDelay].
  incomplete,

  /// The entry ends the way a whole entry does (for a format with no end
  /// marker, always). Flushed after [logLineIdleFlushInterval].
  complete,
}

/// How long a log stream may stay silent before an entry that looks complete
/// is emitted. The tools write a whole entry in one go, so a gap this long
/// almost always falls between entries — and when it doesn't, the rest of the
/// entry becomes a second row rather than being lost.
const Duration logLineIdleFlushInterval = Duration(milliseconds: 100);

/// How long a log stream may stay silent before an entry that looks cut off
/// (see [PendingEntryStatus.incomplete]) is emitted anyway, so a missing end
/// marker can't hide the last entry until the next one arrives.
const Duration logLineIncompleteEntryFlushDelay = Duration(seconds: 1);

/// Parses [lines] with [parser], flushing the entry it holds when [lines]
/// ends or goes quiet (without that, the last entry of a burst would wait for
/// the next line, which may be a long time coming). How long "quiet" is
/// depends on [LogLineParser.pendingEntryStatus]: [idleFlushInterval] for an
/// entry that looks complete, [incompleteEntryFlushDelay] for one that doesn't.
///
/// Silence is sampled on one periodic timer rather than a timer reset per
/// line, which a high-volume stream would pay for on every line. The timer is
/// stopped while the output is paused: the entry's remaining lines may be
/// sitting in the paused source, so silence proves nothing then.
///
/// Errors on [lines] are forwarded after the held entry, which came first. A
/// parser exception is delivered as an error event too, rather than escaping
/// to the zone, so a consumer's `await for` sees it where it would have seen
/// one thrown by an inline parse.
Stream<LogEntry> parseLogLines(
  Stream<String> lines,
  LogLineParser parser, {
  Duration idleFlushInterval = logLineIdleFlushInterval,
  Duration incompleteEntryFlushDelay = logLineIncompleteEntryFlushDelay,
}) {
  late final StreamController<LogEntry> controller;
  StreamSubscription<String>? subscription;
  Timer? idleFlushTimer;
  var sawLineSinceTick = false;
  var quietTicks = 0;

  void emitPending() {
    final pending = parser.flush();
    if (pending != null) controller.add(pending);
  }

  void guarded(void Function() parse) {
    try {
      parse();
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  void onTick(Timer _) {
    if (sawLineSinceTick) {
      sawLineSinceTick = false;
      quietTicks = 0;
      return;
    }
    quietTicks++;
    guarded(() {
      final flushDue = switch (parser.pendingEntryStatus) {
        PendingEntryStatus.none || PendingEntryStatus.awaitingBody => false,
        PendingEntryStatus.complete => true,
        PendingEntryStatus.incomplete =>
          idleFlushInterval * quietTicks >= incompleteEntryFlushDelay,
      };
      if (flushDue) emitPending();
    });
  }

  void startIdleFlushTimer() {
    sawLineSinceTick = false;
    quietTicks = 0;
    idleFlushTimer = Timer.periodic(idleFlushInterval, onTick);
  }

  void stopIdleFlushTimer() {
    idleFlushTimer?.cancel();
    idleFlushTimer = null;
  }

  controller = StreamController<LogEntry>(
    onListen: () {
      startIdleFlushTimer();
      subscription = lines.listen(
        (line) {
          sawLineSinceTick = true;
          guarded(() => parser.addLine(line).forEach(controller.add));
        },
        onError: (Object error, StackTrace stackTrace) {
          guarded(emitPending);
          controller.addError(error, stackTrace);
        },
        onDone: () {
          stopIdleFlushTimer();
          guarded(emitPending);
          controller.close();
        },
      );
    },
    onPause: () {
      stopIdleFlushTimer();
      subscription?.pause();
    },
    onResume: () {
      subscription?.resume();
      startIdleFlushTimer();
    },
    onCancel: () {
      stopIdleFlushTimer();
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
