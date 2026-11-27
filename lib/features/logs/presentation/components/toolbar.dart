import 'package:flutter/material.dart';

import '../../../../presentation/components/feature_view.dart';
import '../../../../presentation/components/overflow_toolbar.dart';
import '../../log_controller.dart';
import '../../log_session_manager.dart';
import 'log_tab_strip.dart';

/// Header of the Logs pane — a standard [FeatureViewHeader] whose title
/// slot holds the log-tab strip. The capture controls (start/restart,
/// pause, clear) are its primary controls and never collapse; the view
/// toggles collapse into the overflow menu as the pane narrows, and copy
/// all, export and import live in that menu only. Imported logs have
/// nothing to capture, so they show no primary controls.
class const Toolbar({
  super.key,
  required final LogController controller,
  required final LogSessionManager logManager,
  required final VoidCallback? onImportLog,
  required final VoidCallback? onExport,
  required final VoidCallback? onCopyAll,
  required final VoidCallback? onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = controller;

    return FeatureViewHeader(
      title: 'Logs',
      tabs: LogTabStrip(logManager: logManager, onImportLog: onImportLog),
      closeTooltip: 'Close logs pane',
      onClose: onClose,
      primary: [
        if (!c.isImported) ...[
          ToolbarAction(
            icon: c.isRunning ? Icons.restart_alt_rounded : Icons.play_arrow,
            label: c.isRunning ? 'Restart' : 'Start',
            tooltip: !c.isConnected
                ? 'Device is disconnected'
                : c.isRunning
                ? 'Restart'
                : 'Start',
            onPressed: c.isConnected ? c.startLogcat : null,
          ),
          ToolbarAction(
            icon: c.isPaused ? Icons.play_arrow : Icons.pause,
            label: c.isPaused ? 'Resume' : 'Pause',
            tooltip: c.isRunning
                ? (c.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            isActive: c.isPaused,
            onPressed: c.isRunning ? c.togglePauseResume : null,
          ),
          ToolbarAction(
            icon: Icons.delete_outline,
            label: 'Clear logs',
            tooltip: c.hasLogs ? 'Clear logs' : 'No logs to clear',
            onPressed: c.hasLogs ? c.clearLogs : null,
          ),
        ],
      ],
      actions: [
        // ── Deselect (only while rows are selected) ───────────────────
        if (c.hasSelectedRows)
          ToolbarAction(
            icon: Icons.deselect_outlined,
            label: 'Clear selected rows',
            onPressed: c.clearSelectedRows,
          ),

        // ── Wrap / auto-scroll (search lives in the filter row) ───────
        ToolbarAction(
          icon: c.wrapText ? Icons.wrap_text : Icons.notes,
          label: 'Wrap long lines',
          tooltip: c.wrapText ? 'Disable Wrap' : 'Enable Wrap',
          isActive: c.wrapText,
          onPressed: c.toggleWrapText,
        ),
        ToolbarAction(
          icon: c.autoScroll ? Icons.vertical_align_bottom : Icons.swipe_down,
          label: 'Auto-scroll',
          tooltip: c.autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          isActive: c.autoScroll,
          onPressed: c.toggleAutoScroll,
        ),

        // ── Menu only: copy everything, export, import ────────────────
        // Row selection mode is the checklist button on the column header.
        ToolbarAction(
          icon: Icons.copy_all_outlined,
          label: 'Copy all logs',
          tooltip: c.hasAnyCachedLogs ? 'Copy all logs' : 'No logs to copy',
          onPressed: c.hasAnyCachedLogs ? onCopyAll : null,
          dividerBefore: true,
          menuOnly: true,
        ),
        ToolbarAction(
          icon: Icons.upload_outlined,
          label: 'Export logs',
          onPressed: onExport,
          menuOnly: true,
        ),
        ToolbarAction(
          icon: Icons.download_outlined,
          label: 'Import log file',
          onPressed: onImportLog,
          menuOnly: true,
        ),
      ],
    );
  }
}
