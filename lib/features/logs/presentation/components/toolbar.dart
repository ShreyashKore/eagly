import 'package:flutter/material.dart';

import '../../../../presentation/components/animation_utils.dart';
import '../../../../presentation/components/overflow_toolbar.dart';
import '../../log_controller.dart';
import '../../log_session_manager.dart';
import 'log_tab_strip.dart';
import 'toolbar_divider.dart';
import 'toolbar_icon_button.dart';

/// Toolbar for the Logs feature: log-tab strip, capture controls
/// (start/pause/clear), copy/row-selection, search, view toggles, export,
/// import, and a pane-level close button.
///
/// The capture controls, the tab strip and the close button are always
/// visible; everything in between collapses into an overflow menu — last
/// action first — as the pane narrows.
class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.controller,
    required this.logManager,
    required this.onImportLog,
    required this.onExport,
    required this.onCopyAll,
    required this.onClose,
  });

  final LogController controller;
  final LogSessionManager logManager;
  final VoidCallback? onImportLog;
  final VoidCallback? onExport;
  final VoidCallback? onCopyAll;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const gap = SizedBox(width: 4);
    const div = ToolbarDivider();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: OverflowToolbar(
        actionBuilder: (context, action) => ToolbarIconButton(
          icon: action.icon,
          tooltip: action.tooltip ?? action.label,
          isActive: action.isActive,
          onPressed: action.onPressed,
        ),
        leading: [
          // ── Live-only capture controls (hidden for imported logs) ──────
          AnimatedSection(
            visible: !c.isImported,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToolbarIconButton(
                  icon: c.isRunning
                      ? Icons.restart_alt_rounded
                      : Icons.play_arrow,
                  tooltip: !c.isConnected
                      ? 'Device is disconnected'
                      : c.isRunning
                      ? 'Restart'
                      : 'Start',
                  onPressed: c.isConnected ? c.startLogcat : null,
                ),
                gap,
                ToolbarIconButton(
                  icon: c.isPaused ? Icons.play_arrow : Icons.pause,
                  tooltip: c.isRunning
                      ? (c.isPaused ? 'Resume' : 'Pause')
                      : 'Not running',
                  isActive: c.isPaused,
                  onPressed: c.isRunning ? c.togglePauseResume : null,
                ),
                gap,
                ToolbarIconButton(
                  icon: Icons.delete_outline,
                  tooltip: c.logs.isNotEmpty
                      ? 'Clear logs'
                      : 'No logs to clear',
                  onPressed: c.logs.isNotEmpty ? c.clearLogs : null,
                ),
                gap,
                div,
                gap,
              ],
            ),
          ),
        ],

        // ── Log tab strip: takes the leftover width and scrolls ─────────
        flexible: LogTabStrip(logManager: logManager, onImportLog: onImportLog),
        flexibleMinWidth: 120,

        actions: [
          // ── Copy / row-select ─────────────────────────────────────────
          ToolbarAction(
            icon: Icons.copy_all_outlined,
            label: 'Copy all logs',
            tooltip: c.hasAnyCachedLogs ? 'Copy all logs' : 'No logs to copy',
            dividerBefore: true,
            onPressed: c.hasAnyCachedLogs ? onCopyAll : null,
          ),
          ToolbarAction(
            icon: c.rowSelectionMode
                ? Icons.checklist_rounded
                : Icons.checklist_outlined,
            label: 'Row selection mode',
            tooltip: c.rowSelectionMode
                ? 'Disable row selection mode'
                : 'Enable row selection mode',
            isActive: c.rowSelectionMode,
            onPressed: c.filteredLogs.isNotEmpty
                ? c.toggleRowSelectionMode
                : null,
          ),

          // ── Deselect (only while rows are selected) ───────────────────
          if (c.hasSelectedRows)
            ToolbarAction(
              icon: Icons.deselect_outlined,
              label: 'Clear selected rows',
              onPressed: c.clearSelectedRows,
            ),

          // ── Search / wrap / auto-scroll ───────────────────────────────
          ToolbarAction(
            icon: Icons.search,
            label: 'Search in logs',
            tooltip: c.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            isActive: c.searchBarVisible,
            dividerBefore: true,
            onPressed: () {
              if (c.searchBarVisible) {
                c.closeSearchBar();
              } else {
                c.activateSearchFromSelection();
              }
            },
          ),
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

          // ── Export / import ───────────────────────────────────────────
          ToolbarAction(
            icon: Icons.upload_outlined,
            label: 'Export logs',
            dividerBefore: true,
            onPressed: onExport,
          ),
          ToolbarAction(
            icon: Icons.download_outlined,
            label: 'Import log file',
            onPressed: onImportLog,
          ),
        ],

        // ── Close (always visible, with its group divider) ──────────────
        trailing: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              div,
              gap,
              ToolbarIconButton(
                icon: Icons.close,
                tooltip: 'Close logs pane',
                onPressed: onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
