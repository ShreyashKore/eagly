import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onCaseSensitiveChanged;
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
    required this.onQueryChanged,
    required this.onCaseSensitiveChanged,
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
    final noResults = hasQuery && widget.totalMatches == 0;
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Container(
        width: 400,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search in logs...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  filled: noResults,
                  fillColor: noResults ? Colors.red[50] : null,
                ),
                onChanged: widget.onQueryChanged,
                onSubmitted: (_) => widget.onNext(),
              ),
            ),

            // Match count
            if (hasQuery)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Text(
                  widget.totalMatches == 0
                      ? 'No results'
                      : '${widget.currentMatch} / ${widget.totalMatches}',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.totalMatches == 0
                        ? Colors.red[700]
                        : Colors.grey[600],
                  ),
                ),
              ),

            const SizedBox(width: 2),

            // Case-sensitive toggle (Aa)
            Tooltip(
              message:
                  'Match case (${widget.caseSensitive ? "on" : "off"})',
              child: GestureDetector(
                onTap: () =>
                    widget.onCaseSensitiveChanged(!widget.caseSensitive),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: widget.caseSensitive
                        ? BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 1,
                            ),
                          )
                        : BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                          ),
                    alignment: Alignment.center,
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.caseSensitive
                            ? theme.colorScheme.primary
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Previous match
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed:
                  widget.totalMatches > 0 ? widget.onPrevious : null,
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
            ),

            // Next match
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.totalMatches > 0 ? widget.onNext : null,
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
            ),

            // Close
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close search (Esc)',
            ),
          ],
        ),
      ),
    );
  }
}
