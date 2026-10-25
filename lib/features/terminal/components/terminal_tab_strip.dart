import 'package:flutter/material.dart';

import '../../../presentation/components/pane_tab_strip.dart';
import '../../../presentation/theme/app_theme.dart';
import '../terminal_session_manager.dart';

/// Horizontally scrolling strip of terminal tabs with a trailing "+" button.
/// A tab shows a live dot while it has a command running, and a pin when it
/// was pointed at a device other than its own.
class const TerminalTabStrip({
  super.key,
  required final TerminalSessionManager manager,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The chips show each tab's live state (running, pinned), so they follow
      // every tab, not just the manager's own tab list.
      listenable: Listenable.merge([manager, ...manager.tabs]),
      builder: (context, _) => PaneTabStrip(
        addTooltip: 'New terminal tab',
        onAdd: manager.addTab,
        tabs: [
          for (final (i, tab) in manager.tabs.indexed)
            PaneTabChip(
              label: manager.labelFor(i),
              selected: i == manager.selectedIndex,
              leading: tab.isRunning
                  ? Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.eaglyTheme.statusLiveColor,
                        shape: BoxShape.circle,
                      ),
                    )
                  : tab.isPinnedElsewhere
                  ? const Icon(Icons.push_pin_outlined)
                  : null,
              tooltip: tab.isRunning
                  ? tab.runningCommand
                  : 'Commands go to ${tab.targetDevice.displayName}',
              onTap: () => manager.selectTab(i),
              onClose: manager.canClose(i) ? () => manager.closeTab(i) : null,
            ),
        ],
      ),
    );
  }
}
