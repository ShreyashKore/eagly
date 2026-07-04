import '../../../utils/log_entry_utils.dart';
import '../../../utils/text_search_pattern.dart';
import '../data/models/log_column.dart';
import '../data/models/log_entry.dart';

List<int> computeSearchMatches(
  List<LogEntry> items,
  Set<String> hiddenColumns,
  bool isIosLogContext,
  TextSearchPattern inlineSearchPattern,
) {
  final pattern = inlineSearchPattern;
  if (!pattern.isActive || !pattern.isValid) return [];

  final visibleColumns = LogColumn.values
      .where((column) => !hiddenColumns.contains(column.name))
      .toList();

  final result = <int>[];
  for (var index = 0; index < items.length; index++) {
    final log = items[index];
    if (log.isSpecialEntry) {
      if (pattern.matches(log.specialSearchableText)) {
        result.add(index);
      }
      continue;
    }
    for (final column in visibleColumns) {
      if (pattern.matches(log.valueForColumn(column, isIos: isIosLogContext))) {
        result.add(index);
        break;
      }
    }
  }
  return result;
}
