class LogTabSettings {
  const LogTabSettings({
    required this.wrapText,
    required this.autoScroll,
    required this.selectedLogLevel,
    required this.logLinesLimit,
    required this.hiddenColumns,
    required this.columnWidths,
  });

  final bool wrapText;
  final bool autoScroll;
  final String selectedLogLevel;
  final int logLinesLimit;
  final Set<String> hiddenColumns;
  final Map<String, double> columnWidths;

  LogTabSettings copyWith({
    bool? wrapText,
    bool? autoScroll,
    String? selectedLogLevel,
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
