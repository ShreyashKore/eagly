import 'log_level.dart';
import 'log_view_mode.dart';

class LogTabSettings {
  const LogTabSettings({
    required this.wrapText,
    required this.autoScroll,
    required this.selectedLogLevel,
    required this.filterViewMode,
    required this.logLinesLimit,
    required this.hiddenColumns,
    required this.columnWidths,
  });

  final bool wrapText;
  final bool autoScroll;
  final LogLevel selectedLogLevel;
  final LogFilterViewMode filterViewMode;
  final int logLinesLimit;
  final Set<String> hiddenColumns;
  final Map<String, double> columnWidths;

  LogTabSettings copyWith({
    bool? wrapText,
    bool? autoScroll,
    LogLevel? selectedLogLevel,
    LogFilterViewMode? filterViewMode,
    int? logLinesLimit,
    Set<String>? hiddenColumns,
    Map<String, double>? columnWidths,
  }) {
    return LogTabSettings(
      wrapText: wrapText ?? this.wrapText,
      autoScroll: autoScroll ?? this.autoScroll,
      selectedLogLevel: selectedLogLevel ?? this.selectedLogLevel,
      filterViewMode: filterViewMode ?? this.filterViewMode,
      logLinesLimit: logLinesLimit ?? this.logLinesLimit,
      hiddenColumns: hiddenColumns != null
          ? Set.of(hiddenColumns)
          : Set.of(this.hiddenColumns),
      columnWidths: columnWidths != null
          ? Map.of(columnWidths)
          : Map.of(this.columnWidths),
    );
  }
}
