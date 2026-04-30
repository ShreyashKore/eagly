import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';

/// Floating search bar for searching within filtered log content.
///
/// Supports:
/// - Text search with live highlighting
/// - Case-sensitive toggle (Aa button)
/// - Previous / Next match navigation
/// - Occurrence count display ("3 / 15")
/// - Escape to close
/// - Enter to go to next match
class LogSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regexSearch;
  final bool hasError;
  final String? errorText;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final ValueChanged<bool> onWholeWordChanged;
  final ValueChanged<bool> onRegexChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  /// 1-based index of the currently focused match (0 when no matches).
  final int currentMatch;
  final int totalMatches;

  const LogSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.caseSensitive,
    required this.wholeWord,
    required this.regexSearch,
    this.hasError = false,
    this.errorText,
    required this.onQueryChanged,
    required this.onCaseSensitiveChanged,
    required this.onWholeWordChanged,
    required this.onRegexChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.currentMatch,
    required this.totalMatches,
  });

  @override
  State<LogSearchBar> createState() => _LogSearchBarState();
}

class _LogSearchBarState extends State<LogSearchBar> {
  late final FocusNode _internalFocusNode = FocusNode();

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;
  bool get _ownsFocusNode => widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    } else {
      _focusNode.onKeyEvent = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.controller.text.isNotEmpty;
    final noResults = hasQuery && widget.totalMatches == 0 && !widget.hasError;
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;
    final hasSearchIssue = noResults || widget.hasError;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Container(
        width: 520,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                // Prevent the default onEditingComplete behavior which can
                // remove focus (especially on some platforms). We'll handle
                // submission explicitly in onSubmitted and then re-request
                // focus so the user can keep pressing Enter to navigate.
                onEditingComplete: () {},
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: 'Search in logs...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  filled: hasSearchIssue,
                  fillColor: widget.hasError
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
                      : (noResults ? logTheme.searchNoResultsFillColor : null),
                ),
                onChanged: widget.onQueryChanged,
                onSubmitted: (_) {
                  widget.onNext();
                  // Re-request focus after the submission so the TextField
                  // doesn't lose focus and users can continue pressing
                  // Enter to go to the next match.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _focusNode.requestFocus();
                    }
                  });
                },
              ),
            ),

            // Match count
            if (hasQuery)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Text(
                  widget.hasError
                      ? 'Invalid regex'
                      : widget.totalMatches == 0
                      ? 'No results'
                      : '${widget.currentMatch} / ${widget.totalMatches}',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.hasError
                        ? theme.colorScheme.error
                        : widget.totalMatches == 0
                        ? logTheme.searchNoResultsTextColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            const SizedBox(width: 2),

            _SearchToggleButton(
              label: '.*',
              tooltip: 'Use regex (${widget.regexSearch ? "on" : "off"})',
              value: widget.regexSearch,
              onPressed: () => widget.onRegexChanged(!widget.regexSearch),
            ),
            const SizedBox(width: 4),
            _SearchToggleButton(
              label: 'W',
              tooltip: 'Match whole word (${widget.wholeWord ? "on" : "off"})',
              value: widget.wholeWord,
              onPressed: () => widget.onWholeWordChanged(!widget.wholeWord),
            ),
            const SizedBox(width: 4),
            _SearchToggleButton(
              label: 'Aa',
              tooltip: 'Match case (${widget.caseSensitive ? "on" : "off"})',
              value: widget.caseSensitive,
              onPressed: () =>
                  widget.onCaseSensitiveChanged(!widget.caseSensitive),
            ),

            // Previous match
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.totalMatches > 0 ? widget.onPrevious : null,
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
            ),

            // Next match
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.totalMatches > 0 ? widget.onNext : null,
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
            ),

            // Close
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              tooltip: widget.hasError && widget.errorText != null
                  ? 'Close search (Esc)\n${widget.errorText!}'
                  : 'Close search (Esc)',
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchToggleButton extends StatelessWidget {
  const _SearchToggleButton({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: value
                ? BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 1,
                    ),
                  )
                : BoxDecoration(borderRadius: BorderRadius.circular(4)),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: value
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

