import 'package:flutter/material.dart';

import '../../log_session_manager.dart';
import 'log_tab_chip.dart';

/// Horizontally scrolling strip of log tabs, with a trailing "+" button for
/// new live tabs (or imports, in the imports-only workspace).
class LogTabStrip extends StatefulWidget {
  const LogTabStrip({super.key, required this.logManager, this.onImportLog});

  final LogSessionManager logManager;

  /// Used by the trailing "+" button in the imports-only workspace, where new
  /// tabs come from importing a file rather than starting a live capture.
  final VoidCallback? onImportLog;

  @override
  State<LogTabStrip> createState() => _LogTabStripState();
}

class _LogTabStripState extends State<LogTabStrip> {
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
                LogTabChip(
                  label: manager.labelFor(i),
                  isImported: manager.tabs[i].isImported,
                  selected: i == manager.selectedIndex,
                  canClose: manager.canClose(i),
                  onTap: () => manager.selectTab(i),
                  onClose: manager.canClose(i)
                      ? () => manager.closeTab(i)
                      : null,
                ),
              // ── + New log tab (or import, in the imports-only workspace) ─
              Tooltip(
                message: manager.isImportsOnly
                    ? 'Import log file'
                    : 'New log tab',
                child: IconButton(
                  onPressed: manager.isImportsOnly
                      ? widget.onImportLog
                      : manager.addLiveTab,
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
