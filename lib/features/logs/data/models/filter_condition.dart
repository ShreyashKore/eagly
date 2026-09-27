import 'log_filters.dart';

/// The log column a classic-bar filter pill constrains. [anyField] is the
/// inline bar's bare word: a substring match over the whole searchable line.
enum FilterConditionField {
  packageName,
  tag,
  pidTid,
  message,
  anyField;

  String label({required bool isIos}) => switch (this) {
    FilterConditionField.packageName => 'Package',
    FilterConditionField.tag => isIos ? 'Category' : 'Tag',
    FilterConditionField.pidTid => 'PID / TID',
    FilterConditionField.message => 'Message',
    FilterConditionField.anyField => 'Any field',
  };

  /// Only [FilterOperator.contains] survives the round trip through inline
  /// syntax for [anyField] (bare words carry no operator), so it offers no
  /// other.
  List<FilterOperator> get operators => this == FilterConditionField.anyField
      ? const [FilterOperator.contains]
      : FilterOperator.values;
}

/// A filter pill's comparison: a [FilterMatchMode] plus negation, named the
/// way a person reads the pill ("Tag is not Chatty").
enum FilterOperator {
  contains(FilterMatchMode.contains, negate: false, label: 'contains'),
  notContains(
    FilterMatchMode.contains,
    negate: true,
    label: 'does not contain',
  ),
  exact(FilterMatchMode.exact, negate: false, label: 'is'),
  notExact(FilterMatchMode.exact, negate: true, label: 'is not'),
  regex(FilterMatchMode.regex, negate: false, label: 'matches regex'),
  notRegex(FilterMatchMode.regex, negate: true, label: 'does not match regex');

  const FilterOperator(this.mode, {required this.negate, required this.label});

  final FilterMatchMode mode;
  final bool negate;
  final String label;

  static FilterOperator of(FilterMatchMode mode, {required bool negate}) =>
      values.firstWhere((op) => op.mode == mode && op.negate == negate);
}

/// One classic-bar filter pill. A pill whose [value] is still blank is a draft:
/// it is shown while being edited but contributes no [FilterTerm].
class FilterCondition {
  const FilterCondition({
    required this.id,
    required this.field,
    this.operator = FilterOperator.contains,
    this.value = '',
  });

  /// Stable identity across edits, so an open editor keeps its pill.
  final int id;
  final FilterConditionField field;
  final FilterOperator operator;
  final String value;

  bool get isDraft => value.trim().isEmpty;

  /// The term this pill contributes, or null while it is a draft.
  FilterTerm? toTerm() {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return FilterTerm(trimmed, mode: operator.mode, negate: operator.negate);
  }

  FilterCondition copyWith({FilterOperator? operator, String? value}) =>
      FilterCondition(
        id: id,
        field: field,
        operator: operator ?? this.operator,
        value: value ?? this.value,
      );
}
