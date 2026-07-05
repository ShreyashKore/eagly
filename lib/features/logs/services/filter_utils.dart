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
  final entryTime = log.parsedTimestamp;
  if (entryTime == null) return true;
  final reference = now ?? DateTime.now();
  return reference.difference(entryTime) <= maxAge;
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
