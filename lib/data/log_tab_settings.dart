import 'log_view_mode.dart';

class LogTabSettings {
  const LogTabSettings({
    required this.wrapText,
    required this.autoScroll,
    required this.selectedLogLevel,
    required this.viewMode,
    required this.logLinesLimit,
    required this.hiddenColumns,
    required this.columnWidths,
  });

  final bool wrapText;
  final bool autoScroll;
  final String selectedLogLevel;
  final LogViewMode viewMode;
  final int logLinesLimit;
  final Set<String> hiddenColumns;
  final Map<String, double> columnWidths;

  LogTabSettings copyWith({
    bool? wrapText,
    bool? autoScroll,
    String? selectedLogLevel,
    LogViewMode? viewMode,
    int? logLinesLimit,
    Set<String>? hiddenColumns,
    Map<String, double>? columnWidths,
  }) {
    return LogTabSettings(
      wrapText: wrapText ?? this.wrapText,
      autoScroll: autoScroll ?? this.autoScroll,
      selectedLogLevel: selectedLogLevel ?? this.selectedLogLevel,
      viewMode: viewMode ?? this.viewMode,
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

