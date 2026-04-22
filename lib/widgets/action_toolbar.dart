import 'package:flutter/material.dart';

class ActionToolbar extends StatelessWidget {
  final VoidCallback? onImport;
  final VoidCallback? onExport;
  final bool wrapText;
  final VoidCallback? onToggleWrap;
  final bool autoScroll;
  final VoidCallback? onToggleAutoScroll;
  final VoidCallback? openSettings;

  const ActionToolbar({
    super.key,
    required this.onImport,
    required this.onExport,
    required this.wrapText,
    required this.onToggleWrap,
    required this.autoScroll,
    required this.onToggleAutoScroll,
    required this.openSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      spacing: 4,
      children: [
        IconButton(
          onPressed: onImport,
          icon: const Icon(Icons.file_download),
          tooltip: 'Import Logcat File',
        ),
        IconButton(
          onPressed: onExport,
          icon: const Icon(Icons.file_upload),
          tooltip: 'Export Logs',
        ),
        IconButton(
          onPressed: onToggleWrap,
          icon: Icon(wrapText ? Icons.wrap_text : Icons.notes),
          tooltip: wrapText ? 'Disable Wrap' : 'Enable Wrap',
        ),
        IconButton(
          onPressed: onToggleAutoScroll,
          icon: Icon(
            autoScroll ? Icons.vertical_align_bottom : Icons.swipe_down,
          ),
          tooltip: autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          color: autoScroll ? colorScheme.primary : null,
        ),
        // IconButton(
        //   onPressed: onCycleViewMode,
        //   icon: Icon(_getViewModeIcon()),
        //   tooltip: _getViewModeTooltip(),
        // ),
        IconButton(
          onPressed: openSettings,
          icon: Icon(Icons.settings_rounded),
          tooltip: 'View settings',
        ),
      ],
    );
  }
}
