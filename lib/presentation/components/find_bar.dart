import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// The find bar shown above searchable text: the query, case and regex
/// toggles, the match count, previous / next and close. ↵ steps forward,
/// ⇧↵ back, Esc closes.
///
/// It only draws; whoever owns the search passes its state in. `CodeView`
/// drives it from re_editor's find controller, the terminal from its own.
class const FindBar({
  super.key,
  required final TextEditingController query,
  final FocusNode? focusNode,
  required final String hint,
  required final bool caseSensitive,
  required final bool regex,
  required final VoidCallback onToggleCaseSensitive,
  required final VoidCallback onToggleRegex,

  /// How many matches the query has, or null while that is still being
  /// worked out.
  required final int? matchCount,

  /// Zero-based index of the current match, when there is one.
  required final int currentIndex,

  /// The query is a regex that doesn't compile.
  final bool invalid = false,
  required final VoidCallback onPrevious,
  required final VoidCallback onNext,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    final isEmpty = query.text.isEmpty;
    final noMatches = !isEmpty && matchCount == 0;
    final hasMatches = (matchCount ?? 0) > 0;

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
                const SingleActivator(LogicalKeyboardKey.enter): onNext,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    onPrevious,
              },
              child: TextField(
                controller: query,
                focusNode: focusNode,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  border: InputBorder.none,
                  filled: noMatches || invalid,
                  fillColor: invalid
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : tokens.searchNoResultsFillColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          _FindToggle(
            label: 'Aa',
            tooltip: 'Match case',
            value: caseSensitive,
            onPressed: onToggleCaseSensitive,
          ),
          _FindToggle(
            label: '.*',
            tooltip: 'Use regular expression',
            value: regex,
            onPressed: onToggleRegex,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              invalid
                  ? 'Invalid regex'
                  : isEmpty
                  ? ''
                  : matchCount == null
                  ? '…'
                  : noMatches
                  ? 'No results'
                  : '${currentIndex + 1} / $matchCount',
              style: theme.textTheme.bodySmall?.copyWith(
                color: invalid
                    ? cs.error
                    : noMatches
                    ? tokens.searchNoResultsTextColor
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
          AppIconButton(
            tooltip: 'Previous match (⇧↵)',
            icon: Icons.keyboard_arrow_up,
            iconSize: 16,
            padding: 4,
            onPressed: hasMatches ? onPrevious : null,
          ),
          AppIconButton(
            tooltip: 'Next match (↵)',
            icon: Icons.keyboard_arrow_down,
            iconSize: 16,
            padding: 4,
            onPressed: hasMatches ? onNext : null,
          ),
          AppIconButton(
            tooltip: 'Close (Esc)',
            icon: Icons.close,
            iconSize: 16,
            padding: 4,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class const _FindToggle({
  required final String label,
  required final String tooltip,
  required final bool value,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$tooltip (${value ? 'on' : 'off'})',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(left: 2),
            width: context.scaled(26),
            height: context.scaled(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? cs.primaryContainer : null,
              borderRadius: BorderRadius.circular(4),
              border: value ? Border.all(color: cs.primary) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: value ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How ⌘[key] / Ctrl+[key] is written on this platform, for tooltips and
/// menus.
String shortcutLabel(String key) =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘$key' : 'Ctrl+$key';
