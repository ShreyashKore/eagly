import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import '../../services/preferences_service.dart';
import 'components/terminal_input_bar.dart';
import 'components/terminal_output_view.dart';
import 'components/terminal_tab_strip.dart';
import 'terminal_controller.dart';
import 'terminal_session_manager.dart';

/// The Terminal pane: a tab strip, the selected tab's scrollback, and the
/// prompt.
///
/// The pane itself holds no terminal knowledge — every tab is a
/// [TerminalController] that knows which device its commands go to and adds the
/// device selector on the way out.
class TerminalFeatureView extends FeatureView {
  const TerminalFeatureView({
    super.key,
    required this.manager,
    required VoidCallback onClose,
  }) : super(onClose: onClose);

  final TerminalSessionManager manager;

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
    await Clipboard.setData(ClipboardData(text: text));
    showSnackBar('Copied the terminal output.');
  }

  @override
  Widget buildContent(BuildContext context) {
    final controller = manager.selectedTab;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildContent(context, controller),
    );
  }

  Widget _buildContent(BuildContext context, TerminalController controller) {
    final theme = Theme.of(context);

    return FeaturePane(
      header: FeatureViewHeader(
        title: 'Terminal',
        onClose: widget.onClose,
        closeTooltip: 'Close terminal pane',
        actions: [
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
    );
  }
}
