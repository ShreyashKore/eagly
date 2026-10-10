import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../terminal_session_manager.dart';
import 'terminal_tab_chip.dart';

/// Horizontally scrolling strip of terminal tabs with a trailing "+" button.
class TerminalTabStrip extends StatefulWidget {
  const TerminalTabStrip({super.key, required this.manager});

  final TerminalSessionManager manager;

  @override
  State<TerminalTabStrip> createState() => _TerminalTabStripState();
}

class _TerminalTabStripState extends State<TerminalTabStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;

    return ListenableBuilder(
      // The chips show each tab's live state (running, pinned), so they follow
      // every tab, not just the manager's own tab list.
      listenable: Listenable.merge([manager, ...manager.tabs]),
      builder: (context, _) => SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < manager.tabs.length; i++)
              TerminalTabChip(
                label: manager.labelFor(i),
                selected: i == manager.selectedIndex,
                isRunning: manager.tabs[i].isRunning,
                isPinned: manager.tabs[i].isPinnedElsewhere,
                tooltip: manager.tabs[i].isRunning
                    ? manager.tabs[i].runningCommand
                    : 'Commands go to ${manager.tabs[i].targetDevice.displayName}',
                onTap: () => manager.selectTab(i),
                onClose: manager.canClose(i) ? () => manager.closeTab(i) : null,
              ),
            AppIconButton(
              tooltip: 'New terminal tab',
              onPressed: manager.addTab,
              iconSize: 16,
              padding: 4,
              icon: Icons.add,
            ),
          ],
        ),
      ),
    );
  }
}
