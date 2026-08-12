import 'package:flutter/material.dart';

import 'inline_filter_suggestion_tile.dart';

/// The autocomplete dropdown for the inline filter bar: a floating card with
/// the scrollable list of [InlineFilterSuggestionTile]s.
class InlineFilterSuggestionsOverlay extends StatelessWidget {
  const InlineFilterSuggestionsOverlay({
    super.key,
    required this.options,
    required this.scrollController,
    required this.highlightedIndex,
    required this.itemKeyBuilder,
    required this.onSelected,
    required this.isIos,
  });

  final List<InlineFilterSuggestion> options;
  final ScrollController scrollController;
  final int highlightedIndex;

  /// Stable per-suggestion key so the highlighted item can be scrolled into
  /// view via `Scrollable.ensureVisible`.
  final Key Function(InlineFilterSuggestion suggestion) itemKeyBuilder;
  final ValueChanged<InlineFilterSuggestion> onSelected;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 540),
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              return InlineFilterSuggestionTile(
                key: itemKeyBuilder(option),
                suggestion: option,
                highlighted: highlightedIndex == index,
                isIos: isIos,
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }
}
