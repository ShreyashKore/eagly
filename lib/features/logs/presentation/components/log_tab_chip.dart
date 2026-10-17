import 'package:flutter/material.dart';

import '../../../../presentation/components/app_icon_button.dart';
import '../../../../presentation/theme/app_theme.dart';

/// A single chip in the log tab strip: label, optional imported marker, and
/// an optional close button.
class LogTabChip extends StatelessWidget {
  const LogTabChip({
    super.key,
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
        : context.eaglyTheme.secondaryTextColor;

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
