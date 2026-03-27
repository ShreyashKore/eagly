import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/log_entry.dart';
import '../utils/log_utils.dart';

/// Table-based log viewer using DataTable2 widget
///
/// This widget displays logs in a spreadsheet-like table format with the following columns:
/// - Timestamp: When the log entry was created
/// - PID/Package: Process ID or package name
/// - TID: Thread ID
/// - Level: Log level (V, D, I, W, E, F)
/// - Tag: Log tag
/// - Message: Log message content
///
/// Usage:
/// ```dart
/// LogViewerTable(
///   logs: myLogEntries,
///   scrollController: myScrollController,
/// )
/// ```
class LogViewerTable extends StatelessWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;

  const LogViewerTable({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: 1200,
        headingRowHeight: 40,
        dataRowHeight: 24,
        headingTextStyle: GoogleFonts.notoSansMono(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        dataTextStyle: GoogleFonts.notoSansMono(
          fontSize: 11,
          height: 1.2,
        ),
        columns: const [
          DataColumn2(
            label: Text('Timestamp'),
            size: ColumnSize.S,
          ),
          DataColumn2(
            label: Text('PID/Package'),
            size: ColumnSize.S,
          ),
          DataColumn2(
            label: Text('TID'),
            size: ColumnSize.S,
            numeric: true,
          ),
          DataColumn2(
            label: Text('Level'),
            size: ColumnSize.S,
          ),
          DataColumn2(
            label: Text('Tag'),
            size: ColumnSize.M,
          ),
          DataColumn2(
            label: Text('Message'),
            size: ColumnSize.L,
          ),
        ],
        rows: logs.map((log) {
          final displayId = log.packageName ?? log.pid;
          final levelColor = LogUtils.colorForLevel(log.level);

          return DataRow2(
            cells: [
              DataCell(
                Text(
                  log.timestamp,
                  style: TextStyle(color: levelColor),
                ),
              ),
              DataCell(
                Text(
                  displayId,
                  style: TextStyle(color: levelColor),
                ),
              ),
              DataCell(
                Text(
                  log.tid,
                  style: TextStyle(color: levelColor),
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    log.level,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              DataCell(
                Text(
                  log.tag,
                  style: TextStyle(color: levelColor),
                ),
              ),
              DataCell(
                Text(
                  log.message,
                  style: TextStyle(color: levelColor),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
