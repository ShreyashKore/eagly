import 'package:flutter/material.dart';

class ActionToolbar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onExport;
  final bool wrapText;
  final VoidCallback onToggleWrap;
  final bool autoScroll;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onScrollToEnd;

  const ActionToolbar({
    super.key,
    required this.onImport,
    required this.onExport,
    required this.wrapText,
    required this.onToggleWrap,
    required this.autoScroll,
    required this.onToggleAutoScroll,
    required this.onScrollToEnd,
  });

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
      ],
    );
  }
}
