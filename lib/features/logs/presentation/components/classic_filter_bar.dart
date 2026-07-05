import 'package:flutter/material.dart';

import '../../data/models/log_filters.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

export 'filter_bar_shared.dart' show filterInputDecoration, kFilterFieldHeight;
export 'log_filter_controller.dart'
    show ClassicFilterController, LogFilterSuggestions;

/// The classic filter bar: separate level / package / tag / message fields.
/// Fully driven by a [ClassicFilterController]; it owns no filter state.
class ClassicFilterBar extends StatelessWidget {
  const ClassicFilterBar({super.key, required this.controller});

  final ClassicFilterController controller;

  bool get _isIos => controller.isIos;
  LogFilterSuggestions get _suggestions => controller.suggestions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildRow(context),
    );
  }

  Widget _buildRow(BuildContext context) {
    return Row(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: LogLevelDropdown(
            selectedLogLevel: controller.selectedLevel,
            onLogLevelChanged: (level) {
              if (level != null) controller.setLevel(level);
            },
            isIos: _isIos,
          ),
        ),
        Expanded(
          flex: 3,
          child: _RecentFilterField(
            controller: controller.packageController,
            focusNode: controller.packageFocusNode,
            onSuggestionSelected: (value) =>
                controller.selectSuggestion(LogFilterField.packageName, value),
            onSubmitted: (_) => controller.applyNow(),
            recentValues: _mergeSuggestedValues([
              for (final entry in _suggestions.recentPackageFilters())
                _SuggestedFilterValue(
                  value: entry,
                  priority: _SuggestionPriority.recent,
                ),
              for (final entry in _suggestions.knownPackageFilters())
                _SuggestedFilterValue(
                  value: entry,
                  priority: _SuggestionPriority.known,
                ),
            ]),
            labelText: 'Package',
            hintText: 'Package / process',
            prefixIcon: Icons.apps_outlined,
            optionLabelBuilder: (option) => option.value,
          ),
        ),
        Expanded(
          flex: 3,
          child: _RecentFilterField(
            controller: controller.tagController,
            focusNode: controller.tagFocusNode,
            onSuggestionSelected: (value) =>
                controller.selectSuggestion(LogFilterField.tag, value),
            onSubmitted: (_) => controller.applyNow(),
            recentValues: _suggestions.recentTagFilters(),
            labelText: _isIos ? 'Category' : 'Tag',
            hintText: _isIos ? 'Filter category…' : 'Filter tag…',
            prefixIcon: Icons.sell_outlined,
          ),
        ),
        Expanded(
          flex: 10,
          child: _RecentFilterField(
            controller: controller.messageController,
            focusNode: controller.messageFocusNode,
            onSuggestionSelected: (value) =>
                controller.selectSuggestion(LogFilterField.message, value),
            onSubmitted: (_) => controller.applyNow(),
            recentValues: _suggestions.recentMessageFilters(),
            labelText: 'Message',
            hintText: 'Filter message text…',
            prefixIcon: Icons.message_outlined,
          ),
        ),
      ],
    );
  }
}

enum _SuggestionPriority { recent, known }

class _SuggestedFilterValue {
  const _SuggestedFilterValue({required this.value, required this.priority});

  final String value;
  final _SuggestionPriority priority;
}

List<_SuggestedFilterValue> _mergeSuggestedValues(
  List<_SuggestedFilterValue> values,
) {
  final deduped = <_SuggestedFilterValue>[];
  final seenValues = <String>{};
  for (final entry in values) {
    final trimmedValue = entry.value.trim();
    if (trimmedValue.isEmpty) continue;
    final normalized = trimmedValue.toLowerCase();
    if (!seenValues.add(normalized)) continue;
    deduped.add(
      _SuggestedFilterValue(value: trimmedValue, priority: entry.priority),
    );
  }
  return deduped;
}

class _RecentFilterField<T extends Object> extends StatelessWidget {
  const _RecentFilterField({
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
