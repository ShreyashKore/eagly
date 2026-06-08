import 'package:flutter/material.dart';

import '../log_controller.dart';
import '../log_session_manager.dart';

/// Toolbar for the Logs feature: log-tab strip, capture controls
/// (start/pause/clear), copy/row-selection, search, view toggles, export,
/// and import. The install feature has moved to the feature rail.
class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.controller,
    required this.logManager,
    required this.onImportLog,
    required this.onExport,
    required this.onCopyAll,
  });

  final LogController controller;
  final LogSessionManager logManager;
  final VoidCallback? onImportLog;
  final VoidCallback? onExport;
  final VoidCallback? onCopyAll;

  @override
  Widget build(BuildContext context) {
    final divider = Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: VerticalDivider(
        width: 2,
        thickness: 2,
        radius: BorderRadius.circular(2),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        spacing: 4,
        children: [
          // ── Live-only capture controls ────────────────────────────────
          if (!controller.isImported) ...[
            ToolbarIconButton(
              icon: controller.isRunning
                  ? Icons.restart_alt_rounded
                  : Icons.play_arrow,
              tooltip: !controller.isConnected
                  ? 'Device is disconnected'
                  : controller.isRunning
                  ? 'Restart'
                  : 'Start',
              onPressed: !controller.isConnected
                  ? null
                  : controller.startLogcat,
            ),
            ToolbarIconButton(
              icon: controller.isPaused ? Icons.play_arrow : Icons.pause,
              tooltip: controller.isRunning
                  ? (controller.isPaused ? 'Resume' : 'Pause')
                  : 'Not running',
              isActive: controller.isPaused,
              onPressed: controller.isRunning
                  ? controller.togglePauseResume
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: controller.logs.isNotEmpty
                  ? 'Clear logs'
                  : 'No logs to clear',
              onPressed: controller.logs.isNotEmpty
                  ? controller.clearLogs
                  : null,
            ),
            divider,
          ],

          // ── Log tab strip ─────────────────────────────────────────────
          _LogTabStrip(logManager: logManager),
          Spacer(),
          divider,

          // ── Copy / row-select ────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: controller.hasAnyCachedLogs
                ? 'Copy all logs'
                : 'No logs to copy',
            onPressed: controller.hasAnyCachedLogs ? onCopyAll : null,
          ),
          ToolbarIconButton(
            icon: controller.rowSelectionMode
                ? Icons.checklist_rounded
                : Icons.checklist_outlined,
            tooltip: controller.rowSelectionMode
                ? 'Disable row selection mode'
                : 'Enable row selection mode',
            isActive: controller.rowSelectionMode,
            onPressed: controller.filteredLogs.isNotEmpty
                ? controller.toggleRowSelectionMode
                : null,
          ),
          if (controller.hasSelectedRows)
            IconButton(
              icon: const Icon(Icons.deselect_outlined),
              tooltip: 'Clear selected rows',
              onPressed: controller.clearSelectedRows,
            ),
          divider,

          // ── Search / wrap / auto-scroll ───────────────────────────────
          ToolbarIconButton(
            icon: Icons.search,
            tooltip: controller.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            isActive: controller.searchBarVisible,
            onPressed: () {
              if (controller.searchBarVisible) {
                controller.closeSearchBar();
              } else {
                controller.activateSearchFromSelection();
              }
            },
          ),
          ToolbarIconButton(
            icon: controller.wrapText ? Icons.wrap_text : Icons.notes,
            tooltip: controller.wrapText ? 'Disable Wrap' : 'Enable Wrap',
            isActive: controller.wrapText,
            onPressed: controller.toggleWrapText,
          ),
          ToolbarIconButton(
            icon: controller.autoScroll
                ? Icons.vertical_align_bottom
                : Icons.swipe_down,
            tooltip: controller.autoScroll
                ? 'Auto-scroll ON'
                : 'Auto-scroll OFF',
            isActive: controller.autoScroll,
            onPressed: controller.toggleAutoScroll,
          ),
          divider,

          // ── Export / import ───────────────────────────────────────────
          IconButton(
            onPressed: onExport,
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export logs',
          ),
          IconButton(
            onPressed: onImportLog,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import log file',
          ),
        ],
      ),
    );
  }
}

// ── Log tab strip ──────────────────────────────────────────────────────────

class _LogTabStrip extends StatefulWidget {
  const _LogTabStrip({required this.logManager});

  final LogSessionManager logManager;

  @override
  State<_LogTabStrip> createState() => _LogTabStripState();
}

class _LogTabStripState extends State<_LogTabStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.logManager,
      builder: (context, _) {
        final manager = widget.logManager;
        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < manager.tabs.length; i++)
                _LogTabChip(
                  label: manager.labelFor(i),
                  isImported: manager.tabs[i].isImported,
                  selected: i == manager.selectedIndex,
                  canClose: manager.canClose(i),
                  onTap: () => manager.selectTab(i),
                  onClose: manager.canClose(i)
                      ? () => manager.closeTab(i)
                      : null,
                ),
              // ── + New live tab ────────────────────────────────────────
              Tooltip(
                message: 'New live log tab',
                child: InkWell(
                  onTap: manager.addLiveTab,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Icon(
                      Icons.add,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogTabChip extends StatelessWidget {
  const _LogTabChip({
    required this.label,
    required this.isImported,
    required this.selected,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool isImported;
  final bool selected;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = selected
        ? (isImported
              ? cs.tertiaryContainer.withValues(alpha: 0.8)
              : cs.secondaryContainer.withValues(alpha: 0.85))
        : Colors.transparent;

    final fg = selected
        ? (isImported ? cs.onTertiaryContainer : cs.onSecondaryContainer)
        : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.only(
              left: 8,
              right: 4,
              top: 3,
              bottom: 3,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? fg.withValues(alpha: 0.25)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isImported) ...[
                  Icon(Icons.description_outlined, size: 11, color: fg),
                  const SizedBox(width: 4),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: fg,
                    ),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(Icons.close, size: 12, color: fg),
                  ),
                ] else
                  const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon button for the toolbar that shows a tinted rounded background when
/// [isActive] is true, making the toggled / enabled state clearly visible.
class ToolbarIconButton extends StatelessWidget {
  const ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// When true the button renders with a tinted rounded background.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final activeBg = colorScheme.primaryContainer.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: onPressed == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? activeColor
                : onPressed == null
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
