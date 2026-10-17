import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';

/// A single chip in the terminal tab strip: label, a live dot while that tab
/// has a command running, and an optional close button.
class TerminalTabChip extends StatelessWidget {
  const TerminalTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.isRunning,
    required this.isPinned,
    required this.onTap,
    required this.onClose,
    this.tooltip,
  });

  final String label;
  final bool selected;

  /// True while this tab has a command running — worth seeing from another tab.
  final bool isRunning;

  /// True when the tab was pointed at a device other than its own.
  final bool isPinned;

  final VoidCallback onTap;
  final VoidCallback? onClose;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

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
                  ? cs.secondaryContainer.withValues(alpha: 0.85)
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
                if (isRunning) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: context.eaglyTheme.statusLiveColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else if (isPinned) ...[
                  Icon(Icons.push_pin_outlined, size: 11, color: fg),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
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
