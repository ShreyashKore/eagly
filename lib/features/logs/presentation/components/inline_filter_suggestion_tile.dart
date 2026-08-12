import 'package:flutter/material.dart';

import '../../data/models/log_level.dart';
import '../../../../presentation/theme/log_level_presentation.dart';

/// A single autocomplete suggestion for the inline filter bar.
class InlineFilterSuggestion {
  const InlineFilterSuggestion({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.level,
    required this.replacementText,
    required this.addTrailingSpace,
    required this.applyImmediately,
    required this.reopenSuggestions,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final LogLevel? level;
  final String replacementText;
  final bool addTrailingSpace;
  final bool applyImmediately;
  final bool reopenSuggestions;
}

/// One row in the inline filter suggestions dropdown: label (or level chip)
/// on the left, subtitle on the right, highlighted when keyboard-selected.
class InlineFilterSuggestionTile extends StatelessWidget {
  const InlineFilterSuggestionTile({
    super.key,
    required this.suggestion,
    required this.highlighted,
    required this.isIos,
    required this.onTap,
  });

  final InlineFilterSuggestion suggestion;
  final bool highlighted;
  final bool isIos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = highlighted
        ? theme.colorScheme.secondaryContainer
        : null;
    final option = suggestion;

    return InkWell(
      onTap: onTap,
      child: ColoredBox(
        color: backgroundColor ?? Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: option.level != null
                    ? LogLevelLabel(
                        level: option.level!,
                        isIos: isIos,
                        text: option.label,
                        compact: true,
                        textStyle: theme.textTheme.bodySmall,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(option.icon, size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: highlighted
                                    ? theme.colorScheme.onSecondaryContainer
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (option.subtitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    option.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: highlighted
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
