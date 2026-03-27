import 'package:flutter/material.dart';
import 'package:worksheet/worksheet.dart';

import '../data/log_entry.dart';
import '../utils/log_utils.dart';

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
class LogViewerWorksheet extends StatelessWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;

  const LogViewerWorksheet({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Build sparse cell data map
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

    // Create sparse worksheet data
    final data = SparseWorksheetData(
      rowCount: logs.length + 1, // +1 for header row
      columnCount: 6,
      cells: cells,
    );

    return WorksheetTheme(
      data: WorksheetThemeData(
        cellPadding: 8.0,
        defaultColumnWidth: 150,
        defaultRowHeight: 24,
      ),
      child: Worksheet(
        data: data,
        rowCount: logs.length + 1,
        columnCount: 6,
      ),
    );
  }
}
