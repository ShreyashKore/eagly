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

  if (!_matchesAllTerms(packageFilterValue(log), appliedFilters.packageTerms)) {
    return false;
  }

  // Only force the cached lowercase concatenation when there's actually a
  // raw-term filter to test against — building it for every entry regardless
  // (even with no raw filter active) doubled per-entry text memory for no
  // reason.
  if (appliedFilters.rawTerms.isNotEmpty &&
      !_matchesAllTerms(log.lowercaseSearchable, appliedFilters.rawTerms)) {
    return false;
  }

  if (appliedFilters.pidTidTerms.isNotEmpty) {
    final candidates = _pidTidCandidates(log);
    if (appliedFilters.pidTidTerms.any(
      (term) => !term.matchesAny(candidates),
    )) {
      return false;
    }
  }

  if (!_matchesAllTerms(log.tag, appliedFilters.tagTerms)) {
    return false;
  }

  if (!_matchesAllTerms(log.message, appliedFilters.messageTerms)) {
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

/// True when every term in [terms] matches [candidate]. An empty [terms] matches
/// everything. Each term applies its own mode (contains/exact/regex) and
/// negation.
bool _matchesAllTerms(String candidate, List<FilterTerm> terms) {
  if (terms.isEmpty) return true;
  return terms.every((term) => term.matches(candidate));
}

/// The pid/tid forms a `pid` term is matched against: the pid, the tid, and the
/// `pid/tid` and `pid:tid` pairs. A term matches when any form matches.
List<String> _pidTidCandidates(LogEntry log) => [
  log.pid,
  log.tid,
  '${log.pid}/${log.tid}',
  '${log.pid}:${log.tid}',
];

/// True when [log] is no older than [maxAge] relative to [now] (defaults to the
/// current time). Entries whose timestamp can't be parsed — e.g. inline status
/// lines with an empty timestamp — are kept, so age never hides those markers.
bool _matchesMaxAge(LogEntry log, Duration maxAge, DateTime? now) {
  final entryTime = log.parsedTimestamp;
  if (entryTime == null) return true;
  final reference = now ?? DateTime.now();
  return reference.difference(entryTime) <= maxAge;
}
