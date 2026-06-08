import 'package:flutter/material.dart';

import '../../../ui/components/animation_utils.dart';
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
    final c = controller;
    const gap = SizedBox(width: 4);
    const div = _ToolbarDivider();
    Widget gapTimes(int n) => SizedBox(width: 4.0 * n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: [
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
                gapTimes(3),
              ],
            ),
          ),

          // ── Log tab strip ─────────────────────────────────────────────
          _LogTabStrip(logManager: logManager),
          const Spacer(),
          gap,
          div,
          gap,

          // ── Copy / row-select ─────────────────────────────────────────
          ToolbarIconButton(
            icon: Icons.copy_all_outlined,
            tooltip: c.hasAnyCachedLogs ? 'Copy all logs' : 'No logs to copy',
            onPressed: c.hasAnyCachedLogs ? onCopyAll : null,
          ),
          gap,
          ToolbarIconButton(
            icon: c.rowSelectionMode
                ? Icons.checklist_rounded
                : Icons.checklist_outlined,
            tooltip: c.rowSelectionMode
                ? 'Disable row selection mode'
                : 'Enable row selection mode',
            isActive: c.rowSelectionMode,
            onPressed: c.filteredLogs.isNotEmpty
                ? c.toggleRowSelectionMode
                : null,
          ),

          // ── Deselect (appears only when rows are selected) ────────────
          AnimatedSection(
            visible: c.hasSelectedRows,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                gap,
                ToolbarIconButton(
                  icon: Icons.deselect_outlined,
                  tooltip: 'Clear selected rows',
                  onPressed: c.clearSelectedRows,
                ),
              ],
            ),
          ),

          gap,
          div,
          gap,

          // ── Search / wrap / auto-scroll ───────────────────────────────
          ToolbarIconButton(
            icon: Icons.search,
            tooltip: c.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            isActive: c.searchBarVisible,
            onPressed: () {
              if (c.searchBarVisible) {
                c.closeSearchBar();
              } else {
                c.activateSearchFromSelection();
              }
            },
          ),
          gap,
          ToolbarIconButton(
            icon: c.wrapText ? Icons.wrap_text : Icons.notes,
            tooltip: c.wrapText ? 'Disable Wrap' : 'Enable Wrap',
            isActive: c.wrapText,
            onPressed: c.toggleWrapText,
          ),
          gap,
          ToolbarIconButton(
            icon: c.autoScroll ? Icons.vertical_align_bottom : Icons.swipe_down,
            tooltip: c.autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            isActive: c.autoScroll,
            onPressed: c.toggleAutoScroll,
          ),
          gap,
          div,
          gap,

          // ── Export / import ───────────────────────────────────────────
          ToolbarIconButton(
            icon: Icons.upload_outlined,
            tooltip: 'Export logs',
            onPressed: onExport,
          ),
          gap,
          ToolbarIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Import log file',
            onPressed: onImportLog,
          ),
        ],
      ),
    );
  }
}

// ── Toolbar divider ────────────────────────────────────────────────────────

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: VerticalDivider(
        width: 2,
        thickness: 2,
        radius: BorderRadius.circular(2),
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
              // ── + New log tab ────────────────────────────────────────
              Tooltip(
                message: 'New log tab',
                child: IconButton(
                  onPressed: manager.addLiveTab,
                  mouseCursor: SystemMouseCursors.click,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  icon: Padding(
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
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.only(
              left: 12,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? fg.withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isImported) ...[
                  Icon(Icons.description_outlined, size: 11, color: fg),
                  const SizedBox(width: 6),
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
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    icon: Icon(Icons.close, size: 12, color: fg),
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

// ── ToolbarIconButton ──────────────────────────────────────────────────────

/// An icon button for the toolbar with smooth transitions for all state
/// changes:
/// - Icon swap (e.g. play → restart): cross-fade + scale via [AnimatedSwitcher].
/// - Color change (enabled ↔ disabled, active ↔ inactive): smooth tween via
///   [TweenAnimationBuilder].
/// - Background tint (active state): [AnimatedContainer].
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

  /// When true, renders with a tinted rounded background.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final targetColor = isActive
        ? cs.primary
        : enabled
        ? cs.onSurfaceVariant
        : cs.onSurface.withValues(alpha: 0.38);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          // AnimatedSwitcher detects icon changes (via ValueKey) and
          // cross-fades + scales the old icon out / new icon in.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.72, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            // TweenAnimationBuilder smoothly interpolates the icon color
            // between state changes (enabled/disabled, active/inactive).
            // Keying by icon ensures a fresh tween whenever the icon itself
            // changes (the AnimatedSwitcher handles that transition instead).
            child: TweenAnimationBuilder<Color?>(
              key: ValueKey(icon),
              duration: const Duration(milliseconds: 250),
              tween: ColorTween(end: targetColor),
              builder: (_, color, __) =>
                  Icon(icon, size: 20, color: color ?? targetColor),
            ),
          ),
        ),
      ),
    );
  }
}
