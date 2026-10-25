import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// A pane's own row of tabs (Logs, Terminal): [tabs] — usually
/// [PaneTabChip]s — scrolling sideways, then a "+" button.
class const PaneTabStrip({
  super.key,
  required final List<Widget> tabs,
  required final String addTooltip,
  required final VoidCallback? onAdd,
}) extends StatefulWidget {
  @override
  State<PaneTabStrip> createState() => _PaneTabStripState();
}

class _PaneTabStripState extends State<PaneTabStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...widget.tabs,
          AppIconButton(
            tooltip: widget.addTooltip,
            onPressed: widget.onAdd,
            iconSize: 16,
            padding: 4,
            icon: Icons.add,
          ),
        ],
      ),
    );
  }
}

/// One tab in a [PaneTabStrip]: a label, an optional [leading] marker and an
/// optional close button, filled while [selected]. Icons in [leading] take
/// the chip's text color.
class const PaneTabChip({
  super.key,
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
  required final VoidCallback? onClose,
  final String? tooltip,
  final Widget? leading,
  final double maxLabelWidth = 110,

  /// The fill and text color while selected; the secondary container's by
  /// default.
  final Color? selectedColor,
  final Color? selectedForeground,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected
        ? selectedForeground ?? cs.onSecondaryContainer
        : context.eaglyTheme.secondaryTextColor;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip ?? label,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor ??
                        cs.secondaryContainer.withValues(alpha: 0.85)
                  : Colors.transparent,
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
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(size: 11, color: fg),
                    child: leading!,
                  ),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
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
                  AppIconButton(
                    tooltip: 'Close tab',
                    onPressed: onClose,
                    iconSize: 12,
                    padding: 2,
                    color: fg,
                    icon: Icons.close,
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
