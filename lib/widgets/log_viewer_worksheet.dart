import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:worksheet/worksheet.dart';

import '../data/log_entry.dart';

/// Table-based log viewer using Worksheet widget (spreadsheet-style)
///
/// This widget displays logs in an Excel-like spreadsheet format with the following columns:
/// - Timestamp: When the log entry was created
/// - PID/Package: Process ID or package name
/// - TID: Thread ID
/// - Level: Log level (V, D, I, W, E, F)
/// - Tag: Log tag
/// - Message: Log message content
///
/// The Worksheet widget provides:
/// - Excel-like cell navigation
/// - Efficient sparse data storage
/// - Smooth scrolling for large datasets
/// - Cell selection capabilities
///
/// Usage:
/// ```dart
/// LogViewerWorksheet(
///   logs: myLogEntries,
///   scrollController: myScrollController,
/// )
/// ```
///
/// Worksheet Data Structure Example:
/// ```dart
/// final data = SparseWorksheetData(
///   rowCount: 100,
///   columnCount: 10,
///   cells: {
///     (0, 0): 'Name'.cell,
///     (0, 1): 'Amount'.cell,
///     (1, 0): 'Apples'.cell,
///     (1, 1): 42.cell,
///     (2, 1): '=2+42'.formula,
///   }
/// );
/// ```
class LogViewerWorksheet extends StatefulWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;

  const LogViewerWorksheet({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  State<LogViewerWorksheet> createState() => _LogViewerWorksheetState();
}

class _LogViewerWorksheetState extends State<LogViewerWorksheet> {
  /// Cached worksheet data - only rebuilt when logs change
  SparseWorksheetData? _cachedData;

  /// Track the last logs list length to detect changes
  int _lastLogsLength = -1;

  /// Track the last log's hashCode to detect content changes
  int _lastLogHashCode = 0;

  /// Builds the worksheet data from logs list
  ///
  /// Note on isolates: Moving this to an isolate is NOT beneficial because:
  /// 1. Cell objects can't be passed between isolates (not serializable)
  /// 2. The main cost is object creation, not CPU-intensive computation
  /// 3. Serialization overhead would exceed the simple iteration cost
  /// 4. The logs list is already capped at ~10,000 entries
  SparseWorksheetData _buildWorksheetDataSync(List<LogEntry> logs) {
    final cells = <(int, int), Cell>{};

    // Header row (row 0)
    cells[(0, 0)] = 'Timestamp'.cell;
    cells[(0, 1)] = 'PID/Package'.cell;
    cells[(0, 2)] = 'TID'.cell;
    cells[(0, 3)] = 'Level'.cell;
    cells[(0, 4)] = 'Tag'.cell;
    cells[(0, 5)] = 'Message'.cell;

    // Populate log entries (starting from row 1)
    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      final rowIndex = i + 1;
      final displayId = log.packageName ?? log.pid;

      cells[(rowIndex, 0)] = log.timestamp.cell;
      cells[(rowIndex, 1)] = displayId.cell;
      cells[(rowIndex, 2)] = log.tid.cell;
      cells[(rowIndex, 3)] = log.level.cell;
      cells[(rowIndex, 4)] = log.tag.cell;
      cells[(rowIndex, 5)] = log.message.cell;
    }

    return SparseWorksheetData(
      rowCount: logs.length + 1,
      columnCount: 6,
      cells: cells,
    );
  }

  /// Updates cached data if logs have changed
  void _updateCacheIfNeeded() {
    final currentLength = widget.logs.length;
    final currentHashCode = widget.logs.isNotEmpty ? widget.logs.last.hashCode : 0;

    // Check if we need to rebuild the data
    if (_cachedData == null ||
        _lastLogsLength != currentLength ||
        _lastLogHashCode != currentHashCode) {
      _cachedData = _buildWorksheetDataSync(widget.logs);
      _lastLogsLength = currentLength;
      _lastLogHashCode = currentHashCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateCacheIfNeeded();

    // Show empty worksheet while building or if no data
    final data = _cachedData ?? SparseWorksheetData(
      rowCount: 1,
      columnCount: 6,
      cells: {
        (0, 0): 'Timestamp'.cell,
        (0, 1): 'PID/Package'.cell,
        (0, 2): 'TID'.cell,
        (0, 3): 'Level'.cell,
        (0, 4): 'Tag'.cell,
        (0, 5): 'Message'.cell,
      },
    );

    return WorksheetTheme(
      data: WorksheetThemeData(
        cellPadding: 8.0,
        defaultColumnWidth: 150,
        defaultRowHeight: 24,
        cellBackgroundColor: Colors.transparent,
        fontFamily: GoogleFonts.notoSansMono().fontFamily ?? 'monospace',
      ),
      child: Worksheet(
        data: data,
        freezeConfig: FreezeConfig(frozenRows: 1),
        rowCount: widget.logs.length + 1,
        readOnly: true,
        customColumnWidths: {0: 100, 1: 100, 3: 50, 4: 200, 5: 1000},
        columnCount: 6,
      ),
    );
  }
}
