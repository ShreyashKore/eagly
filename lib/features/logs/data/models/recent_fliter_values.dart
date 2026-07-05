import 'package:eagly/features/logs/data/models/log_filters.dart';

/// In-memory, per-field history of recently applied filter values, offered as
/// autocomplete suggestions. Never persisted to disk.
class RecentFilterValues {
  RecentFilterValues({this.maxPerField = 8});

  /// Maximum values retained per field.
  final int maxPerField;

  final List<String> _message = [];
  final List<String> _package = [];
  final List<String> _pidTid = [];
  final List<String> _tag = [];

  List<String> get message => _message;
  List<String> get package => _package;
  List<String> get pidTid => _pidTid;
  List<String> get tag => _tag;

  /// Records the applied [filters]' per-field terms as the most recent values.
  /// Only plain (case-insensitive contains, non-negated) terms are kept — an
  /// exact/regex/negated term is not a reusable literal to re-suggest.
  void rememberFrom(LogFilters filters) {
    _rememberTerms(_message, filters.messageTerms);
    _rememberTerms(_package, filters.packageTerms);
    _rememberTerms(_pidTid, filters.pidTidTerms);
    _rememberTerms(_tag, filters.tagTerms);
  }

  void _rememberTerms(List<String> recents, List<FilterTerm> terms) {
    for (final term in terms) {
      if (term.mode != FilterMatchMode.contains || term.negate) continue;
      _addRecentValue(recents, term.value, maxPerField);
    }
  }
}

/// Inserts [value] at the front of [recents] (case-insensitively de-duplicated),
/// capping the list at [max]. Blank values are ignored.
void _addRecentValue(List<String> recents, String value, int max) {
  final normalized = value.trim();
  if (normalized.isEmpty) return;

  recents.removeWhere(
    (existing) => existing.toLowerCase() == normalized.toLowerCase(),
  );
  recents.insert(0, normalized);

  if (recents.length > max) {
    recents.removeRange(max, recents.length);
  }
}
