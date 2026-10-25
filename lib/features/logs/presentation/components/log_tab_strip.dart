import 'package:flutter/material.dart';

import '../../../../presentation/components/pane_tab_strip.dart';
import '../../log_session_manager.dart';

/// Horizontally scrolling strip of log tabs, with a trailing "+" button for
/// new live tabs (or imports, in the imports-only workspace). An imported
/// file's tab is marked and tinted apart from the live ones.
class const LogTabStrip({
  super.key,
  required final LogSessionManager logManager,

  /// Used by the trailing "+" button in the imports-only workspace, where new
  /// tabs come from importing a file rather than starting a live capture.
  final VoidCallback? onImportLog,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: logManager,
      builder: (context, _) {
        final manager = logManager;
        return PaneTabStrip(
          // ── + New log tab (or import, in the imports-only workspace) ─
          addTooltip: manager.isImportsOnly ? 'Import log file' : 'New log tab',
          onAdd: manager.isImportsOnly ? onImportLog : manager.addLiveTab,
          tabs: [
            for (final (i, tab) in manager.tabs.indexed)
              PaneTabChip(
                label: manager.labelFor(i),
                selected: i == manager.selectedIndex,
                maxLabelWidth: 90,
                leading: tab.isImported
                    ? const Icon(Icons.description_outlined)
                    : null,
                selectedColor: tab.isImported
                    ? cs.tertiaryContainer.withValues(alpha: 0.8)
                    : null,
                selectedForeground: tab.isImported
                    ? cs.onTertiaryContainer
                    : null,
                onTap: () => manager.selectTab(i),
                onClose: manager.canClose(i) ? () => manager.closeTab(i) : null,
              ),
          ],
        );
      },
    );
  }
}
