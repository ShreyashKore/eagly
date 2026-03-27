import 'package:flutter/material.dart';

/// View mode options for the log viewer
enum LogViewMode {
  text,       // Original text-based viewer
  dataTable,  // DataTable2-based table viewer
  worksheet,  // Worksheet-based spreadsheet viewer
}

class ActionToolbar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onExport;
  final bool wrapText;
  final VoidCallback onToggleWrap;
  final bool autoScroll;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onScrollToEnd;
  final LogViewMode viewMode;
  final VoidCallback onCycleViewMode;

  const ActionToolbar({
    super.key,
    required this.onImport,
    required this.onExport,
    required this.wrapText,
    required this.onToggleWrap,
    required this.autoScroll,
    required this.onToggleAutoScroll,
    required this.onScrollToEnd,
    required this.viewMode,
    required this.onCycleViewMode,
  });

  IconData _getViewModeIcon() {
    switch (viewMode) {
      case LogViewMode.text:
        return Icons.view_list;
      case LogViewMode.dataTable:
        return Icons.table_chart;
      case LogViewMode.worksheet:
        return Icons.grid_on;
    }
  }

  String _getViewModeTooltip() {
    switch (viewMode) {
      case LogViewMode.text:
        return 'Text View (click for DataTable)';
      case LogViewMode.dataTable:
        return 'DataTable View (click for Worksheet)';
      case LogViewMode.worksheet:
        return 'Worksheet View (click for Text)';
    }
  }

  Color? _getViewModeColor() {
    switch (viewMode) {
      case LogViewMode.text:
        return null;
      case LogViewMode.dataTable:
        return Colors.green;
      case LogViewMode.worksheet:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onImport,
          icon: const Icon(Icons.file_open),
          tooltip: 'Import Logcat File',
        ),
        IconButton(
          onPressed: onExport,
          icon: const Icon(Icons.save),
          tooltip: 'Export Logs',
        ),
        IconButton(
          onPressed: onToggleWrap,
          icon: Icon(wrapText ? Icons.wrap_text : Icons.notes),
          tooltip: wrapText ? 'Disable Wrap' : 'Enable Wrap',
        ),
        IconButton(
          onPressed: onToggleAutoScroll,
          icon: Icon(autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
          tooltip: autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          color: autoScroll ? Colors.blue : null,
        ),
        IconButton(
          onPressed: onScrollToEnd,
          icon: const Icon(Icons.arrow_downward),
          tooltip: 'Scroll to End',
        ),
        IconButton(
          onPressed: onCycleViewMode,
          icon: Icon(_getViewModeIcon()),
          tooltip: _getViewModeTooltip(),
          color: _getViewModeColor(),
        ),
      ],
    );
  }
}
