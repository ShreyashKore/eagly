// -- Filter helpers

import 'package:eagly/features/logs/data/models/log_entry.dart';

import '../data/models/log_filters.dart';
import '../data/models/log_level.dart';

bool matchesLogFilters(
  LogEntry log,
  LogFilters appliedFilters,
  LogLevel effectiveSelectedLogLevel, {
  DateTime? now,
}) {
  final selectedLevel = effectiveSelectedLogLevel;
  if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
    return false;
  }

  final maxAge = appliedFilters.maxAge;
  if (maxAge != null && !_matchesMaxAge(log, maxAge, now)) {
    return false;
  }

  if (!_matchesAllTerms(
    packageFilterValue(log),
    appliedFilters.packageTerms,
    caseSensitive: false,
  )) {
    return false;
  }

  if (!_matchesAllTerms(
    log.lowercaseSearchable,
    appliedFilters.rawTerms,
    caseSensitive: false,
  )) {
    return false;
  }

  if (appliedFilters.pidTidTerms.any(
    (query) => !_matchesPidTidFilter(log, query),
  )) {
    return false;
  }

  if (!_matchesAllTerms(
    log.tag,
    appliedFilters.tagTerms,
    caseSensitive: false,
  )) {
    return false;
  }

  if (!_matchesAllTerms(
    log.message,
    appliedFilters.messageTerms,
    caseSensitive: false,
  )) {
    return false;
  }

  return true;
}

/// The package/process name used for package filtering + known-package
/// suggestions. Prefers the package name, falling back to the process name.
String packageFilterValue(LogEntry log) {
  final packageName = log.packageName?.trim();
  if (packageName != null && packageName.isNotEmpty) return packageName;

  final processName = log.processName?.trim();
  if (processName != null && processName.isNotEmpty) return processName;

  return '';
}

/// True when every term in [terms] is contained in [candidate]. An empty
/// [terms] matches everything.
bool _matchesAllTerms(
  String candidate,
  List<String> terms, {
  required bool caseSensitive,
}) {
  if (terms.isEmpty) return true;
  final normalizedCandidate = caseSensitive
      ? candidate
      : candidate.toLowerCase();
  return terms.every((term) {
    final normalizedTerm = caseSensitive ? term : term.toLowerCase();
    return normalizedCandidate.contains(normalizedTerm);
  });
}

/// True when [log] is no older than [maxAge] relative to [now] (defaults to the
/// current time). Entries whose timestamp can't be parsed — e.g. inline status
/// lines with an empty timestamp — are kept, so age never hides those markers.
bool _matchesMaxAge(LogEntry log, Duration maxAge, DateTime? now) {
  final reference = now ?? DateTime.now();
  final entryTime = parseLogEntryTimestamp(log.timestamp, now: reference);
  if (entryTime == null) return true;
  return reference.difference(entryTime) <= maxAge;
}

final RegExp _fullTimestampPattern = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$',
);

final RegExp _shortTimestampPattern = RegExp(
  r'^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$',
);

/// Parses a [LogEntry.timestamp] into a local [DateTime], or null when the
/// format isn't recognised. Handles the iOS-normalised `YYYY-MM-DD HH:MM:SS.mmm`
/// form and the Android logcat `MM-DD HH:MM:SS.mmm` form (no year — inferred
/// from [now], stepping back a year for a date that would otherwise sit in the
/// future across a Dec→Jan boundary).
DateTime? parseLogEntryTimestamp(String timestamp, {DateTime? now}) {
  final trimmed = timestamp.trim();
  if (trimmed.isEmpty) return null;
  final reference = now ?? DateTime.now();

  int millisFrom(String? fraction) {
    if (fraction == null || fraction.isEmpty) return 0;
    final padded = fraction.padRight(3, '0').substring(0, 3);
    return int.parse(padded);
  }

  final full = _fullTimestampPattern.firstMatch(trimmed);
  if (full != null) {
    return DateTime(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
      int.parse(full.group(4)!),
      int.parse(full.group(5)!),
      int.parse(full.group(6)!),
      millisFrom(full.group(7)),
    );
  }

  final short = _shortTimestampPattern.firstMatch(trimmed);
  if (short != null) {
    final month = int.parse(short.group(1)!);
    final day = int.parse(short.group(2)!);
    final hour = int.parse(short.group(3)!);
    final minute = int.parse(short.group(4)!);
    final second = int.parse(short.group(5)!);
    final millis = millisFrom(short.group(6));
    var candidate = DateTime(
      reference.year,
      month,
      day,
      hour,
      minute,
      second,
      millis,
    );
    if (candidate.isAfter(reference.add(const Duration(days: 1)))) {
      candidate = DateTime(
        reference.year - 1,
        month,
        day,
        hour,
        minute,
        second,
        millis,
      );
    }
    return candidate;
  }

  return null;
}

/// True when [query] matches the log's pid, tid, or a `pid/tid` / `pid:tid`
/// pair.
bool _matchesPidTidFilter(LogEntry log, String query) {
  final pid = log.pid.toLowerCase();
  final tid = log.tid.toLowerCase();
  return pid.contains(query) ||
      tid.contains(query) ||
      '$pid/$tid'.contains(query) ||
      '$pid:$tid'.contains(query);
}
