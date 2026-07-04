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
  void rememberFrom(LogFilters filters) {
    for (final value in filters.messageTerms) {
      _addRecentValue(_message, value, maxPerField);
    }
    for (final value in filters.packageTerms) {
      _addRecentValue(_package, value, maxPerField);
    }
    for (final value in filters.pidTidTerms) {
      _addRecentValue(_pidTid, value, maxPerField);
    }
    for (final value in filters.tagTerms) {
      _addRecentValue(_tag, value, maxPerField);
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
