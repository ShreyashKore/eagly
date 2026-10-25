import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/components/feature_view.dart';
import '../../presentation/components/find_bar.dart';
import '../../presentation/components/overflow_toolbar.dart';
import '../../services/preferences_service.dart';
import 'components/terminal_input_bar.dart';
import 'components/terminal_output_view.dart';
import 'components/terminal_tab_strip.dart';
import 'terminal_controller.dart';
import 'terminal_find.dart';
import 'terminal_session_manager.dart';
import '../../presentation/components/snack_bars.dart';

/// The Terminal pane: a tab strip, the selected tab's scrollback, and the
/// prompt.
///
/// The pane itself holds no terminal knowledge — every tab is a
/// [TerminalController] that knows which device its commands go to and adds the
/// device selector on the way out.
class const TerminalFeatureView({
  super.key,
  required final TerminalSessionManager manager,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

  @override
  State<TerminalFeatureView> createState() => _TerminalFeatureViewState();
}

class _TerminalFeatureViewState extends FeatureViewState<TerminalFeatureView> {
  TerminalSessionManager get manager => widget.manager;

  @override
  Listenable get listenable => manager;

  Future<void> _copyScrollback(TerminalController controller) async {
    final text = controller.scrollbackText;
    if (text.isEmpty) return;
    await copyWithToast(context, text, 'Copied the terminal output.');
  }

  @override
  Widget buildContent(BuildContext context) {
    final controller = manager.selectedTab;

    return AnimatedBuilder(
      animation: Listenable.merge([controller, controller.find]),
      builder: (context, _) => _buildContent(context, controller),
    );
  }

  void _toggleFind(TerminalFind find) =>
      find.isOpen ? find.close() : find.open();

  Widget _buildContent(BuildContext context, TerminalController controller) {
    final theme = Theme.of(context);
    final find = controller.find;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): find.open,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            find.open,
      },
      child: FeaturePane(
        header: FeatureViewHeader(
          title: 'Terminal',
          onClose: widget.onClose,
          closeTooltip: 'Close terminal pane',
          actions: [
            ToolbarAction(
              icon: Icons.search,
              label: 'Find',
              tooltip: find.isOpen
                  ? 'Close find (Esc)'
                  : 'Find in output (${shortcutLabel('F')})',
              isActive: find.isOpen,
              onPressed: () => _toggleFind(find),
            ),
            ToolbarAction(
              icon: Icons.copy_all_outlined,
              label: 'Copy output',
              onPressed: controller.lines.isEmpty
                  ? null
                  : () => _copyScrollback(controller),
            ),
            ToolbarAction(
              icon: Icons.clear_all,
              label: 'Clear scrollback',
              tooltip: 'Clear scrollback (Ctrl+L)',
              onPressed: controller.lines.isEmpty ? null : controller.clear,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: TerminalTabStrip(manager: manager),
            ),
            if (find.isOpen)
              FindBar(
                query: find.query,
                focusNode: find.focusNode,
                hint: 'Find in output',
                caseSensitive: find.caseSensitive,
                regex: find.regex,
                onToggleCaseSensitive: find.toggleCaseSensitive,
                onToggleRegex: find.toggleRegex,
                matchCount: find.matches.length,
                currentIndex: find.currentIndex,
                invalid: find.isInvalid,
                onPrevious: find.previous,
                onNext: find.next,
                onClose: find.close,
              ),
            Expanded(
              child: ValueListenableBuilder<double>(
                valueListenable: PreferencesService.logFontSizeListenable,
                builder: (context, fontSize, _) => Column(
                  children: [
                    Expanded(
                      // Keyed per tab so each keeps its own scroll position and
                      // half-typed command rather than inheriting the last tab's.
                      child: TerminalOutputView(
                        key: ObjectKey(controller),
                        lines: controller.lines,
                        find: find,
                        fontSize: fontSize,
                      ),
                    ),
                    TerminalInputBar(
                      key: ObjectKey(controller),
                      controller: controller,
                      fontSize: fontSize,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
