import 'package:flutter/material.dart';

import '../../../../presentation/components/app_icon_button.dart';
import '../../log_session_manager.dart';
import 'log_tab_chip.dart';

/// Horizontally scrolling strip of log tabs, with a trailing "+" button for
/// new live tabs (or imports, in the imports-only workspace).
class const LogTabStrip({
  super.key,
  required final LogSessionManager logManager,

  /// Used by the trailing "+" button in the imports-only workspace, where new
  /// tabs come from importing a file rather than starting a live capture.
  final VoidCallback? onImportLog,
}) extends StatefulWidget {
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
              AppIconButton(
                tooltip: manager.isImportsOnly
                    ? 'Import log file'
                    : 'New log tab',
                onPressed: manager.isImportsOnly
                    ? widget.onImportLog
                    : manager.addLiveTab,
                iconSize: 16,
                padding: 4,
                icon: Icons.add,
              ),
            ],
          ),
        );
      },
    );
  }
}
