import 'log_level.dart';

class const LogTabSettings({
  required final bool wrapText,
  required final bool autoScroll,
  required final LogLevel selectedLogLevel,
  required final int logLinesLimit,
  required final Set<String> hiddenColumns,
  required final Map<String, double> columnWidths,
}) {
  LogTabSettings copyWith({
    bool? wrapText,
    bool? autoScroll,
    LogLevel? selectedLogLevel,
    int? logLinesLimit,
    Set<String>? hiddenColumns,
    Map<String, double>? columnWidths,
  }) {
    return LogTabSettings(
      wrapText: wrapText ?? this.wrapText,
      autoScroll: autoScroll ?? this.autoScroll,
      selectedLogLevel: selectedLogLevel ?? this.selectedLogLevel,
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
