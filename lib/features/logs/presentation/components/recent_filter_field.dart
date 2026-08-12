import 'package:flutter/material.dart';

import 'filter_bar_shared.dart';

/// A filter text field with an autocomplete dropdown of recent/known values.
class RecentFilterField<T extends Object> extends StatelessWidget {
  const RecentFilterField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSuggestionSelected,
    required this.onSubmitted,
    required this.recentValues,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.optionLabelBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSuggestionSelected;
  final ValueChanged<String> onSubmitted;
  final List<T> recentValues;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;
  final String Function(T option)? optionLabelBuilder;

  String _optionLabel(T option) =>
      optionLabelBuilder?.call(option) ?? '$option';

  List<T> _matchingOptions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recentValues.toList(growable: false);

    final preferredMatches = <T>[];
    final secondaryMatches = <T>[];
    for (final option in recentValues) {
      final label = _optionLabel(option);
      final normalized = label.toLowerCase();
      if (!normalized.contains(q)) continue;
      final bucket = filterBoundaryMatch(normalized, q)
          ? preferredMatches
          : secondaryMatches;
      bucket.add(option);
    }

    return [...preferredMatches, ...secondaryMatches];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kFilterFieldHeight,
      child: RawAutocomplete<T>(
        textEditingController: controller,
        focusNode: focusNode,
        optionsBuilder: (textEditingValue) =>
            _matchingOptions(textEditingValue.text),
        onSelected: (value) => onSuggestionSelected(_optionLabel(value)),
        fieldViewBuilder:
            (context, fieldController, fieldFocusNode, onFieldSubmitted) {
              return TextField(
                controller: fieldController,
                focusNode: fieldFocusNode,
                style: const TextStyle(fontSize: 12),
                decoration: filterInputDecoration(
                  context,
                  labelText: labelText,
                  hintText: hintText,
                  prefixIcon: prefixIcon,
                ),
                onSubmitted: (value) {
                  onSubmitted(value);
                  onFieldSubmitted();
                },
              );
            },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          _optionLabel(option),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
